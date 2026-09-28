import Foundation
import Speech
import AVFoundation
import os

// The seams `SpeechRecognitionService` sits on. `SpeechRecognitionServiceProtocol` fakes the
// whole service, so it cannot exercise the stop / timeout / error logic that lives inside it.
// These protocols sit one level lower, around the recognizer and the microphone, which are the
// two things a unit test cannot run.

// MARK: - Recognizer seam

/// What a recognition task reports back. Exactly one `final` or `failure` ends a task.
nonisolated enum SpeechRecognitionEvent: Sendable {
    case partial(String)
    case final(String)
    case failure(any Error)
}

/// A running live (buffer-fed) recognition task.
nonisolated protocol SpeechLiveRecognitionTask: AnyObject, Sendable {
    /// Called from the audio thread.
    func append(_ buffer: AVAudioPCMBuffer)
    /// No more audio is coming. The recognizer still owes a `final` or `failure` event.
    func endAudio()
    /// Drops the task, including a final result that has not been delivered yet.
    func cancel()
}

nonisolated protocol SpeechRecognitionEngine: Sendable {
    func requestAuthorization() async -> Bool
    func isAvailable(for language: SpeechLanguage) -> Bool

    /// `onEvent` may be called on any thread.
    func startLiveTask(
        language: SpeechLanguage,
        onEvent: @escaping @Sendable (SpeechRecognitionEvent) -> Void
    ) throws -> any SpeechLiveRecognitionTask

    /// Transcribes a whole audio file and returns the final text, which may be empty.
    func transcribeFile(at url: URL, language: SpeechLanguage) async throws -> String
}

// MARK: - Microphone seam

nonisolated protocol SpeechAudioInput: AnyObject, Sendable {
    var isRunning: Bool { get }

    func requestPermission() async -> Bool
    /// `onBuffer` is called on the audio thread.
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    /// Stops capturing and returns what was recorded. Empty when nothing was captured.
    func stop() -> Data
    /// Stops capturing and throws the recording away.
    func cancel()
}

// MARK: - SFSpeechRecognizer implementation

nonisolated struct SFSpeechRecognitionEngine: SpeechRecognitionEngine {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.nandamochammad.Reflect",
        category: "Speech"
    )

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func isAvailable(for language: SpeechLanguage) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))?.isAvailable ?? false
    }

    func startLiveTask(
        language: SpeechLanguage,
        onEvent: @escaping @Sendable (SpeechRecognitionEvent) -> Void
    ) throws -> any SpeechLiveRecognitionTask {
        let recognizer = try makeRecognizer(for: language)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        configureOnDevice(request, recognizer: recognizer, language: language)

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                onEvent(.failure(error))
            } else if let result {
                let text = result.bestTranscription.formattedString
                onEvent(result.isFinal ? .final(text) : .partial(text))
            }
        }

        return SFLiveRecognitionTask(recognizer: recognizer, request: request, task: task)
    }

    func transcribeFile(at url: URL, language: SpeechLanguage) async throws -> String {
        let recognizer = try makeRecognizer(for: language)

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        configureOnDevice(request, recognizer: recognizer, language: language)

        // The callback can fire again after the final result or the error, and a
        // continuation must resume exactly once. Holding the recognizer in the run keeps
        // it alive until the task has ended.
        let run = SFFileRecognitionRun(recognizer: recognizer)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.start(continuation: continuation, request: request)
            }
        } onCancel: {
            // The caller gave up, for example on a timeout. Without this the recognition
            // task would keep running with nobody waiting for it.
            run.cancel()
        }
    }

    private func makeRecognizer(for language: SpeechLanguage) throws -> SFSpeechRecognizer {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)) else {
            throw TranscriptionError.languageNotSupported
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }
        return recognizer
    }

    private func configureOnDevice(
        _ request: SFSpeechRecognitionRequest,
        recognizer: SFSpeechRecognizer,
        language: SpeechLanguage
    ) {
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            Self.logger.notice(
                "No on-device recognition for \(language.rawValue, privacy: .public). Using the server, so the result depends on the network."
            )
        }
    }
}

private nonisolated final class SFLiveRecognitionTask: SpeechLiveRecognitionTask, @unchecked Sendable {
    // Held so the recognizer outlives the task it started.
    private let recognizer: SFSpeechRecognizer
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let task: SFSpeechRecognitionTask

    init(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        task: SFSpeechRecognitionTask
    ) {
        self.recognizer = recognizer
        self.request = request
        self.task = task
    }

    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
    func endAudio() { request.endAudio() }
    func cancel() { task.cancel() }
}

/// One file recognition task and the continuation waiting for it.
private nonisolated final class SFFileRecognitionRun: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<String, any Error>?
        var task: SFSpeechRecognitionTask?
        var isCancelled = false
    }

    private let recognizer: SFSpeechRecognizer
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    func start(continuation: CheckedContinuation<String, any Error>, request: SFSpeechURLRecognitionRequest) {
        let wasCancelled = state.withLockUnchecked { state in
            state.continuation = continuation
            return state.isCancelled
        }
        guard !wasCancelled else {
            finish(.failure(TranscriptionError.cancelled))
            return
        }

        let task = recognizer.recognitionTask(with: request) { [self] result, error in
            if let error {
                finish(.failure(error))
            } else if let result, result.isFinal {
                finish(.success(result.bestTranscription.formattedString))
            }
        }

        let cancelledMeanwhile = state.withLockUnchecked { state in
            state.task = task
            return state.isCancelled
        }
        if cancelledMeanwhile { task.cancel() }
    }

    func cancel() {
        let task = state.withLockUnchecked { state in
            state.isCancelled = true
            return state.task
        }
        task?.cancel()
        finish(.failure(TranscriptionError.cancelled))
    }

    private func finish(_ result: Result<String, any Error>) {
        let continuation = state.withLockUnchecked { state in
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume(with: result)
    }
}

// MARK: - AVAudioEngine implementation

nonisolated final class AVAudioEngineSpeechInput: SpeechAudioInput, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.nandamochammad.Reflect",
        category: "Speech"
    )

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    // Written on the audio thread only, so one failed write is logged once, not per buffer.
    private var didLogWriteFailure = false

    var isRunning: Bool {
        audioEngine?.isRunning ?? false
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsPath.appendingPathComponent("voice_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)

        didLogWriteFailure = false
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            onBuffer(buffer)
            self?.write(buffer, to: file)
        }

        audioEngine = engine
        audioFile = file
        recordingURL = url

        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }
    }

    func stop() -> Data {
        stopEngine()
        // Releasing the file closes it, which is what makes the data on disk complete.
        audioFile = nil

        guard let url = recordingURL else { return Data() }
        defer { removeRecording() }

        do {
            return try Data(contentsOf: url)
        } catch {
            Self.logger.error("Could not read the speech recording: \(error.localizedDescription, privacy: .public)")
            return Data()
        }
    }

    func cancel() {
        stopEngine()
        audioFile = nil
        removeRecording()
    }

    private func stopEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    private func write(_ buffer: AVAudioPCMBuffer, to file: AVAudioFile) {
        do {
            try file.write(from: buffer)
        } catch {
            guard !didLogWriteFailure else { return }
            didLogWriteFailure = true
            Self.logger.error("Could not write the speech recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeRecording() {
        guard let url = recordingURL else { return }
        recordingURL = nil

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Could not delete the speech recording: \(error.localizedDescription, privacy: .public)")
        }
    }
}
