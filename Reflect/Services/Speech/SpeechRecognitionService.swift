import Foundation
import Speech
import AVFoundation
import Combine

final class SpeechRecognitionService: NSObject, SpeechRecognitionServiceProtocol {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var currentLanguage: Constants.SpeechLanguage = .english

    private var recordingURL: URL?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var lastUIUpdateTime: Date?

    private let transcribedTextSubject = CurrentValueSubject<String, Never>("")
    private let recordingStateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let audioLevelSubject = PassthroughSubject<Float, Never>()

    // MARK: - UI Update Throttling

    private let uiUpdateInterval: TimeInterval = 0.5  // Update UI every 500ms

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }

    var transcribedText: String {
        transcribedTextSubject.value
    }

    var transcribedTextPublisher: AnyPublisher<String, Never> {
        transcribedTextSubject.eraseToAnyPublisher()
    }

    var recordingStatePublisher: AnyPublisher<RecordingState, Never> {
        recordingStateSubject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    func requestPermission() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let audioStatus = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return speechStatus && audioStatus
    }

    func startRecording(language: Constants.SpeechLanguage) async throws {
        let hasPermission = await requestPermission()
        guard hasPermission else {
            throw TranscriptionError.notAuthorized
        }

        cancelRecording()

        currentLanguage = language
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }

        recordingStateSubject.send(.preparing)
        transcribedTextSubject.send("")

        do {
            try setupAudioSession()
            try setupAudioEngine()
            try setupRecordingFile()

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else {
                throw TranscriptionError.recognitionFailed
            }

            request.shouldReportPartialResults = true
            request.addsPunctuation = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result = result {
                    self?.transcribedTextSubject.send(result.bestTranscription.formattedString)
                }

                if error != nil || (result?.isFinal ?? false) {
                    // Keep recording even if recognition has issues
                }
            }

            recordingStartTime = Date()
            audioEngine?.prepare()
            try audioEngine?.start()

            recordingStateSubject.send(.recording(duration: 0))
            startDurationTimer()
        } catch {
            recordingStateSubject.send(.failed(error.localizedDescription))
            throw error
        }
    }

    func stopRecording() async throws -> VoiceRecordingResult {
        guard isRecording else {
            throw TranscriptionError.cancelled
        }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())

        recordingStateSubject.send(.processing)

        // Wait for final transcription with timeout instead of fixed delay
        let finalTranscription = await waitForFinalTranscription(timeout: 2.0)

        guard let url = recordingURL else {
            throw TranscriptionError.recognitionFailed
        }

        let audioData = try Data(contentsOf: url)
        let transcription = finalTranscription ?? transcribedTextSubject.value

        let result = VoiceRecordingResult(
            audioData: audioData,
            transcription: transcription.isEmpty ? nil : transcription,
            language: currentLanguage.rawValue,
            duration: duration
        )

        recordingStateSubject.send(.completed(result))
        cleanup()

        return result
    }

    func cancelRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        cleanup()
        recordingStateSubject.send(.idle)
        transcribedTextSubject.send("")
    }

    // MARK: - Private Methods

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func setupAudioEngine() throws {
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw TranscriptionError.audioEngineError
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // Write audio buffer to file
            if let audioFile = self?.audioFile {
                try? audioFile.write(from: buffer)
            }

            // Calculate audio level
            let level = self?.calculateAudioLevel(buffer: buffer) ?? 0
            self?.audioLevelSubject.send(level)
        }
    }

    private func setupRecordingFile() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "voice_\(UUID().uuidString).m4a"
        recordingURL = documentsPath.appendingPathComponent(fileName)

        guard let url = recordingURL, let audioEngine = audioEngine else {
            throw TranscriptionError.audioEngineError
        }

        let format = audioEngine.inputNode.outputFormat(forBus: 0)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioFile = try AVAudioFile(forWriting: url, settings: settings)
    }

    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                sum += abs(channelData[channel][frame])
            }
        }

        let average = sum / Float(channelCount * frameLength)
        return min(1, average * 10)
    }

    private func startDurationTimer() {
        Task {
            while isRecording {
                let now = Date()
                let duration = Date().timeIntervalSince(recordingStartTime ?? Date())

                // Throttle UI updates - only update every 500ms instead of every 100ms
                if lastUpdateTime == nil || now.timeIntervalSince(lastUpdateTime!) >= uiUpdateInterval {
                    await MainActor.run {
                        recordingStateSubject.send(.recording(duration: duration))
                    }
                    lastUpdateTime = now
                }

                // Check max duration
                if duration >= Double(Constants.Limits.maxVoiceDurationMinutes * 60) {
                    _ = try? await stopRecording()
                    break
                }

                try? await Task.sleep(nanoseconds: 100_000_000)  // Check every 100ms
            }
        }
    }

    // MARK: - Timeout-based Final Transcription Wait

    private func waitForFinalTranscription(timeout: TimeInterval) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            // Wait for final transcription
            group.addTask {
                // Monitor for changes in transcription
                let initialText = self.transcribedTextSubject.value
                var lastText = initialText
                let startTime = Date()

                while Date().timeIntervalSince(startTime) < timeout {
                    try? await Task.sleep(nanoseconds: 100_000_000)  // Check every 100ms

                    let currentText = self.transcribedTextSubject.value
                    if currentText != initialText, currentText.count > initialText.count {
                        lastText = currentText
                    }

                    // If we haven't received updates in 500ms, consider transcription complete
                    if Date().timeIntervalSince(startTime) >= 0.5 {
                        let checkTime = Date()
                        var stableCount = 0
                        while Date().timeIntervalSince(checkTime) < 0.5 && stableCount < 5 {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            if self.transcribedTextSubject.value == lastText {
                                stableCount += 1
                            } else {
                                lastText = self.transcribedTextSubject.value
                            }
                        }
                        if stableCount >= 5 {
                            break
                        }
                    }
                }

                return lastText.isEmpty ? nil : lastText
            }

            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil  // Timeout - return nil
            }

            // Return first non-nil result
            for await result in group {
                if let result = result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private func cleanup() {
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        audioFile = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recordingStartTime = nil
    }
}
