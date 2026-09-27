import Foundation
import AVFoundation
import Combine
import os

final class SpeechRecognitionService: SpeechRecognitionServiceProtocol {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    /// One live recognition run, from `startLiveTask` until its final result or error.
    private final class LiveSession {
        var task: (any SpeechLiveRecognitionTask)?
        let startTime = Date()
        var lastText = ""
        var ending: Ending?
        var waiter: CheckedContinuation<Ending, Never>?
    }

    /// How a live session ended.
    private enum Ending {
        case final(String)
        case failure(any Error)
        case timedOut
    }

    // MARK: - State

    private var session: LiveSession?
    private var currentLanguage: Constants.SpeechLanguage = .english
    /// Why the last `startRecording` did not get a recognizer running, so `stopRecording`
    /// can report it.
    private var startFailure: TranscriptionError?
    /// Bumped by every start, stop and cancel. A start that finds it changed after an
    /// `await` was overtaken and must not bring the microphone up.
    private var generation = 0
    private var lastUIUpdateTime: Date?

    private let transcribedTextSubject = CurrentValueSubject<String, Never>("")
    private let recordingStateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let audioLevelSubject = PassthroughSubject<Float, Never>()

    // MARK: - UI Update Throttling

    private let uiUpdateInterval: TimeInterval = 0.5  // Update UI every 500ms

    // MARK: - Dependencies

    private let engine: any SpeechRecognitionEngine
    private let audioInput: any SpeechAudioInput
    private let sleep: Sleep
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.nandamochammad.Reflect",
        category: "Speech"
    )

    // MARK: - Initialization

    init(
        engine: any SpeechRecognitionEngine = SFSpeechRecognitionEngine(),
        audioInput: any SpeechAudioInput = AVAudioEngineSpeechInput(),
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.engine = engine
        self.audioInput = audioInput
        self.sleep = sleep
    }

    // MARK: - SpeechRecognitionServiceProtocol

    var isRecording: Bool {
        audioInput.isRunning
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
        let speechStatus = await engine.requestAuthorization()
        let audioStatus = await audioInput.requestPermission()

        return speechStatus && audioStatus
    }

    func startRecording(language: Constants.SpeechLanguage) async throws {
        generation += 1
        let myGeneration = generation
        startFailure = nil

        do {
            guard await requestPermission() else {
                throw TranscriptionError.notAuthorized
            }
            // Stop or cancel arrived while the permission request was pending. The caller
            // already has its answer, so starting now would leave the microphone running
            // with nobody left to stop it.
            guard myGeneration == generation else {
                throw TranscriptionError.cancelled
            }

            discardSession()

            currentLanguage = language
            guard engine.isAvailable(for: language) else {
                throw TranscriptionError.notAvailable
            }

            recordingStateSubject.send(.preparing)
            transcribedTextSubject.send("")

            let newSession = LiveSession()
            let task = try engine.startLiveTask(language: language) { [weak self, weak newSession] event in
                // The recognizer calls back on its own queue. The main queue keeps the
                // events in the order they arrived.
                DispatchQueue.main.async {
                    guard let self, let newSession else { return }
                    self.handle(event, in: newSession)
                }
            }
            newSession.task = task
            session = newSession

            try audioInput.start { [weak self] buffer in
                task.append(buffer)
                let level = Self.audioLevel(of: buffer)
                DispatchQueue.main.async {
                    self?.audioLevelSubject.send(level)
                }
            }

            recordingStateSubject.send(.recording(duration: 0))
            startDurationTimer(for: newSession)
        } catch {
            let failure = Self.transcriptionError(from: error)
            if myGeneration == generation {
                discardSession()
                startFailure = failure
                recordingStateSubject.send(.failed(failure.localizedDescription))
            }
            logger.error("Speech recognition did not start: \(String(describing: error), privacy: .public)")
            throw failure
        }
    }

    func stopRecording() async throws -> VoiceRecordingResult {
        generation += 1

        guard let session else {
            // No recognizer ran, so there is nothing to wait for. This is an outcome, not
            // a thrown error, so the caller can fall back to `transcribe(audioData:)`.
            let outcome: TranscriptionOutcome = startFailure.map { .recognizerFailed($0) } ?? .recognizerDidNotRun
            logger.notice("Stop without a running recognizer: \(String(describing: outcome), privacy: .public)")
            return VoiceRecordingResult(
                audioData: Data(),
                transcription: nil,
                language: currentLanguage.rawValue,
                duration: 0,
                outcome: outcome
            )
        }
        self.session = nil

        let audioData = audioInput.stop()
        // `endAudio()` asks for the final result. Cancelling here would drop it.
        session.task?.endAudio()

        let duration = Date().timeIntervalSince(session.startTime)
        recordingStateSubject.send(.processing)

        let ending = await waitForEnding(of: session, timeout: Self.finalResultTimeout(forDuration: duration))
        if case .timedOut = ending {
            logger.error("No final result within the timeout. Using the last partial text.")
            session.task?.cancel()
        }

        let (text, outcome) = classify(ending, lastText: session.lastText)
        let result = VoiceRecordingResult(
            audioData: audioData,
            transcription: text.isEmpty ? nil : text,
            language: currentLanguage.rawValue,
            duration: duration,
            outcome: outcome
        )

        transcribedTextSubject.send(text)
        recordingStateSubject.send(.completed(result))

        return result
    }

    func cancelRecording() {
        generation += 1
        startFailure = nil
        discardSession()
        recordingStateSubject.send(.idle)
        transcribedTextSubject.send("")
    }

    func transcribe(audioData: Data, language: Constants.SpeechLanguage) async -> VoiceRecordingResult {
        func result(_ text: String, _ outcome: TranscriptionOutcome) -> VoiceRecordingResult {
            VoiceRecordingResult(
                audioData: audioData,
                transcription: text.isEmpty ? nil : text,
                language: language.rawValue,
                duration: 0,
                outcome: outcome
            )
        }

        guard await engine.requestAuthorization() else {
            logger.error("File transcription skipped: speech recognition is not authorized.")
            return result("", .recognizerFailed(.notAuthorized))
        }
        guard engine.isAvailable(for: language) else {
            logger.error("File transcription skipped: no recognizer for \(language.rawValue, privacy: .public).")
            return result("", .recognizerFailed(.notAvailable))
        }

        // The recorder deletes its own file once it has read it, so the caller only has
        // the bytes. The recognizer only reads files.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe_\(UUID().uuidString).m4a")
        do {
            try audioData.write(to: url, options: .atomic)
        } catch {
            logger.error("Could not write the audio for transcription: \(error.localizedDescription, privacy: .public)")
            return result("", .recognizerFailed(.audioFileUnavailable))
        }
        defer {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Could not delete the transcription file: \(error.localizedDescription, privacy: .public)")
            }
        }

        let ending: Ending
        do {
            ending = .final(try await engine.transcribeFile(at: url, language: language))
        } catch {
            ending = .failure(error)
        }

        let (text, outcome) = classify(ending, lastText: "")
        return result(text, outcome)
    }

    // MARK: - Final Result Timeout

    /// How long `stopRecording` waits for the final result: a quarter of the recording,
    /// at least 3 seconds and at most 15.
    nonisolated static func finalResultTimeout(forDuration duration: TimeInterval) -> TimeInterval {
        min(15, max(3, duration * 0.25))
    }

    // MARK: - Private Helpers

    private func handle(_ event: SpeechRecognitionEvent, in session: LiveSession) {
        // A session that was cancelled or replaced has an ending already, which makes
        // whatever its recognizer still sends stale.
        guard session.ending == nil else { return }

        switch event {
        case .partial(let text):
            session.lastText = text
            transcribedTextSubject.send(text)
        case .final(let text):
            session.lastText = text
            transcribedTextSubject.send(text)
            finish(session, with: .final(text))
        case .failure(let error):
            // Recording goes on without the recognizer. The error is reported on stop.
            logger.error("Speech recognition failed: \(String(describing: error), privacy: .public)")
            finish(session, with: .failure(error))
        }
    }

    private func finish(_ session: LiveSession, with ending: Ending) {
        guard session.ending == nil else { return }
        session.ending = ending
        session.waiter?.resume(returning: ending)
        session.waiter = nil
    }

    private func waitForEnding(of session: LiveSession, timeout: TimeInterval) async -> Ending {
        if let ending = session.ending { return ending }

        let timeoutTask = Task { [sleep, weak self] in
            do {
                try await sleep(timeout)
            } catch {
                // Cancelled because the recognizer answered first.
                return
            }
            self?.finish(session, with: .timedOut)
        }
        defer { timeoutTask.cancel() }

        return await withCheckedContinuation { continuation in
            session.waiter = continuation
        }
    }

    private func classify(_ ending: Ending, lastText: String) -> (text: String, outcome: TranscriptionOutcome) {
        switch ending {
        case .final(let text):
            return text.isEmpty ? ("", .noSpeechDetected) : (text, .transcribed)
        case .timedOut:
            return lastText.isEmpty ? ("", .recognizerFailed(.timedOut)) : (lastText, .transcribed)
        case .failure(let error):
            if Self.isNoSpeech(error) {
                return lastText.isEmpty ? ("", .noSpeechDetected) : (lastText, .transcribed)
            }
            return (lastText, .recognizerFailed(Self.transcriptionError(from: error)))
        }
    }

    /// `kAFAssistantErrorDomain` 1110 is the recognizer saying it heard no speech.
    private static func isNoSpeech(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110
    }

    private static func transcriptionError(from error: any Error) -> TranscriptionError {
        (error as? TranscriptionError) ?? .recognitionFailed
    }

    private func discardSession() {
        if let session {
            session.task?.cancel()
            finish(session, with: .failure(TranscriptionError.cancelled))
        }
        session = nil
        audioInput.cancel()
        lastUIUpdateTime = nil
    }

    private nonisolated static func audioLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return 0 }

        var sum: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                sum += abs(channelData[channel][frame])
            }
        }

        let average = sum / Float(channelCount * frameLength)
        return min(1, average * 10)
    }

    private func startDurationTimer(for session: LiveSession) {
        Task { [weak self] in
            while let self, self.session === session, self.isRecording {
                let now = Date()
                let duration = now.timeIntervalSince(session.startTime)

                // Throttle UI updates - only update every 500ms instead of every 100ms
                if lastUIUpdateTime == nil || now.timeIntervalSince(lastUIUpdateTime!) >= uiUpdateInterval {
                    recordingStateSubject.send(.recording(duration: duration))
                    lastUIUpdateTime = now
                }

                // Check max duration
                if duration >= Double(Constants.Limits.maxVoiceDurationMinutes * 60) {
                    do {
                        _ = try await stopRecording()
                    } catch {
                        logger.error("Stop at the max duration failed: \(error.localizedDescription, privacy: .public)")
                    }
                    break
                }

                do {
                    try await Task.sleep(nanoseconds: 100_000_000)  // Check every 100ms
                } catch {
                    break
                }
            }
        }
    }
}
