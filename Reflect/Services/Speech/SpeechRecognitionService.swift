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

    private let transcribedTextSubject = CurrentValueSubject<String, Never>("")
    private let recordingStateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let audioLevelSubject = PassthroughSubject<Float, Never>()

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

        // Wait a moment for final transcription
        try await Task.sleep(nanoseconds: 500_000_000)

        guard let url = recordingURL else {
            throw TranscriptionError.recognitionFailed
        }

        let audioData = try Data(contentsOf: url)
        let transcription = transcribedTextSubject.value

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
                let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
                await MainActor.run {
                    recordingStateSubject.send(.recording(duration: duration))
                }

                // Check max duration
                if duration >= Double(Constants.Limits.maxVoiceDurationMinutes * 60) {
                    _ = try? await stopRecording()
                    break
                }

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
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
