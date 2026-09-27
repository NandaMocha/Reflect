import Foundation
import AVFoundation
import os
@testable import Reflect

/// A live task that behaves like `SFSpeechRecognitionTask` where it matters for the service:
/// once cancelled it delivers nothing more, so a final result sent after `cancel()` is lost.
nonisolated final class FakeLiveRecognitionTask: SpeechLiveRecognitionTask, @unchecked Sendable {
    private struct State {
        var didEndAudio = false
        var didCancel = false
        var onEndAudio: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let onEvent: @Sendable (SpeechRecognitionEvent) -> Void

    init(onEvent: @escaping @Sendable (SpeechRecognitionEvent) -> Void) {
        self.onEvent = onEvent
    }

    var didEndAudio: Bool { state.withLock { $0.didEndAudio } }
    var didCancel: Bool { state.withLock { $0.didCancel } }

    /// Runs when the service calls `endAudio()`, which is when a real recognizer starts
    /// working on its final result.
    func whenAudioEnds(_ action: @escaping @Sendable () -> Void) {
        state.withLock { $0.onEndAudio = action }
    }

    func emit(_ event: SpeechRecognitionEvent) {
        guard !didCancel else { return }
        onEvent(event)
    }

    func append(_ buffer: AVAudioPCMBuffer) {}

    func endAudio() {
        let action = state.withLock { state in
            state.didEndAudio = true
            return state.onEndAudio
        }
        action?()
    }

    func cancel() {
        state.withLock { $0.didCancel = true }
    }
}

nonisolated final class FakeSpeechRecognitionEngine: SpeechRecognitionEngine, @unchecked Sendable {
    private struct State {
        var isAuthorized = true
        var isAvailable = true
        var holdsAuthorization = false
        var pendingAuthorizations: [CheckedContinuation<Bool, Never>] = []
        var liveTasks: [FakeLiveRecognitionTask] = []
        var fileResult: Result<String, any Error> = .success("")
        var transcribedFiles: [URL] = []
        var fileExistedDuringTranscription = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isAuthorized: Bool {
        get { state.withLock { $0.isAuthorized } }
        set { state.withLock { $0.isAuthorized = newValue } }
    }

    var isAvailable: Bool {
        get { state.withLock { $0.isAvailable } }
        set { state.withLock { $0.isAvailable = newValue } }
    }

    /// When true, `requestAuthorization()` does not return until `releaseAuthorization()`.
    var holdsAuthorization: Bool {
        get { state.withLock { $0.holdsAuthorization } }
        set { state.withLock { $0.holdsAuthorization = newValue } }
    }

    var fileResult: Result<String, any Error> {
        get { state.withLock { $0.fileResult } }
        set { state.withLock { $0.fileResult = newValue } }
    }

    var liveTasks: [FakeLiveRecognitionTask] { state.withLock { $0.liveTasks } }
    var transcribedFiles: [URL] { state.withLock { $0.transcribedFiles } }
    var fileExistedDuringTranscription: Bool { state.withLock { $0.fileExistedDuringTranscription } }
    var hasPendingAuthorization: Bool { state.withLock { !$0.pendingAuthorizations.isEmpty } }

    func releaseAuthorization() {
        let (pending, granted) = state.withLock { state in
            defer { state.pendingAuthorizations = [] }
            state.holdsAuthorization = false
            return (state.pendingAuthorizations, state.isAuthorized)
        }
        pending.forEach { $0.resume(returning: granted) }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            let granted: Bool? = state.withLock { state in
                guard state.holdsAuthorization else { return state.isAuthorized }
                state.pendingAuthorizations.append(continuation)
                return nil
            }
            if let granted {
                continuation.resume(returning: granted)
            }
        }
    }

    func isAvailable(for language: SpeechLanguage) -> Bool {
        isAvailable
    }

    func startLiveTask(
        language: SpeechLanguage,
        onEvent: @escaping @Sendable (SpeechRecognitionEvent) -> Void
    ) throws -> any SpeechLiveRecognitionTask {
        let task = FakeLiveRecognitionTask(onEvent: onEvent)
        state.withLock { $0.liveTasks.append(task) }
        return task
    }

    func transcribeFile(at url: URL, language: SpeechLanguage) async throws -> String {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let result = state.withLock { state in
            state.transcribedFiles.append(url)
            state.fileExistedDuringTranscription = exists
            return state.fileResult
        }
        return try result.get()
    }
}

nonisolated final class FakeSpeechAudioInput: SpeechAudioInput, @unchecked Sendable {
    private struct State {
        var isRunning = false
        var startCount = 0
    }

    static let recordedData = Data("recorded audio".utf8)

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isRunning: Bool { state.withLock { $0.isRunning } }
    var startCount: Int { state.withLock { $0.startCount } }

    func requestPermission() async -> Bool { true }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        state.withLock { state in
            state.isRunning = true
            state.startCount += 1
        }
    }

    func stop() -> Data {
        state.withLock { $0.isRunning = false }
        return Self.recordedData
    }

    func cancel() {
        state.withLock { $0.isRunning = false }
    }
}

/// Stands in for `Task.sleep` so a test decides when the timeout fires instead of waiting
/// for it.
nonisolated final class FakeSleep: @unchecked Sendable {
    private struct State {
        var requested: [TimeInterval] = []
        var pending: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var requested: [TimeInterval] { state.withLock { $0.requested } }

    /// Lets every pending sleep finish, which is the timeout firing.
    func fire() {
        let pending = state.withLock { state in
            defer { state.pending = [] }
            return state.pending
        }
        pending.forEach { $0.resume() }
    }

    func sleep(_ seconds: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                state.requested.append(seconds)
                state.pending.append(continuation)
            }
        }
        try Task.checkCancellation()
    }
}
