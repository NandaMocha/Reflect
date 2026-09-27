import Foundation
import Testing
@testable import Reflect

@MainActor
struct SpeechRecognitionServiceTests {
    let engine = FakeSpeechRecognitionEngine()
    let audioInput = FakeSpeechAudioInput()
    let sleep = FakeSleep()
    let service: SpeechRecognitionService

    init() {
        let sleep = sleep
        service = SpeechRecognitionService(
            engine: engine,
            audioInput: audioInput,
            sleep: { try await sleep.sleep($0) }
        )
    }

    // MARK: - Stop keeps the final result

    @Test func stopReturnsTheFinalResultDeliveredAfterEndAudio() async throws {
        let task = try await startRecording()
        task.emit(.partial("hello"))
        task.whenAudioEnds { task.emit(.final("hello world")) }

        let result = try await service.stopRecording()
        sleep.fire()

        #expect(result.transcription == "hello world")
        #expect(result.outcome == .transcribed)
        #expect(result.audioData == FakeSpeechAudioInput.recordedData)
        #expect(task.didEndAudio)
        // The bug: `cancel()` right after `endAudio()` dropped the final result.
        #expect(!task.didCancel)
    }

    @Test func stopKeepsAFinalResultThatArrivesAfterTheOldTwoSecondWindow() async throws {
        let task = try await startRecording()
        task.emit(.partial("hello"))

        async let stopped = service.stopRecording()
        try await waitUntil { !sleep.requested.isEmpty }

        // The service is still waiting, and it waits longer than the old 2 seconds.
        let timeout = try #require(sleep.requested.first)
        #expect(timeout >= 3)
        task.emit(.final("hello world, a bit late"))
        // The final result is already queued, so it wins. Firing the timeout behind it only
        // makes a dropped result fail this test instead of hanging it.
        sleep.fire()

        let result = try await stopped

        #expect(result.transcription == "hello world, a bit late")
        #expect(result.outcome == .transcribed)
        #expect(!task.didCancel)
    }

    @Test func stopUsesTheLastPartialTextWhenTheTimeoutFires() async throws {
        let task = try await startRecording()
        task.emit(.partial("hello"))

        async let stopped = service.stopRecording()
        try await waitUntil { !sleep.requested.isEmpty }
        sleep.fire()

        let result = try await stopped

        #expect(result.transcription == "hello")
        #expect(result.outcome == .transcribed)
        #expect(task.didCancel)
    }

    @Test func stopReportsATimeoutWithoutAnyTextAsFailed() async throws {
        let task = try await startRecording()

        async let stopped = service.stopRecording()
        try await waitUntil { !sleep.requested.isEmpty }
        sleep.fire()

        let result = try await stopped

        #expect(result.transcription == nil)
        #expect(result.outcome == .recognizerFailed(.timedOut))
        #expect(task.didCancel)
    }

    @Test(arguments: [
        (0.0, 3.0),
        (8.0, 3.0),
        (12.0, 3.0),
        (20.0, 5.0),
        (60.0, 15.0),
        (300.0, 15.0)
    ])
    func finalResultTimeoutFollowsTheRecordingLength(duration: TimeInterval, expected: TimeInterval) {
        #expect(SpeechRecognitionService.finalResultTimeout(forDuration: duration) == expected)
    }

    // MARK: - Errors are classified

    @Test func recognizerErrorOnStopProducesTheFailedOutcome() async throws {
        let task = try await startRecording()
        task.whenAudioEnds { task.emit(.failure(Self.recognizerError(code: 1101))) }

        let result = try await service.stopRecording()
        sleep.fire()

        #expect(result.transcription == nil)
        #expect(result.outcome == .recognizerFailed(.recognitionFailed))
    }

    @Test func recognizerErrorDuringRecordingProducesTheFailedOutcome() async throws {
        let task = try await startRecording()
        task.emit(.partial("hello"))
        task.emit(.failure(Self.recognizerError(code: 1101)))
        await flushMainQueue()

        // The microphone keeps going. Only the transcript is affected.
        #expect(service.isRecording)

        let result = try await service.stopRecording()

        #expect(result.outcome == .recognizerFailed(.recognitionFailed))
        #expect(result.transcription == "hello")
        // Nothing to wait for, so no timeout was started.
        #expect(sleep.requested.isEmpty)
    }

    @Test func emptyFinalResultProducesNoSpeech() async throws {
        let task = try await startRecording()
        task.whenAudioEnds { task.emit(.final("")) }

        let result = try await service.stopRecording()
        sleep.fire()

        #expect(result.transcription == nil)
        #expect(result.outcome == .noSpeechDetected)
    }

    @Test func noSpeechErrorProducesNoSpeech() async throws {
        let task = try await startRecording()
        task.whenAudioEnds { task.emit(.failure(Self.recognizerError(code: 1110))) }

        let result = try await service.stopRecording()
        sleep.fire()

        #expect(result.transcription == nil)
        #expect(result.outcome == .noSpeechDetected)
    }

    @Test func stopAfterAStartThatWasNotAuthorizedProducesTheFailedOutcome() async throws {
        engine.isAuthorized = false

        await #expect(throws: TranscriptionError.notAuthorized) {
            try await service.startRecording(language: .english)
        }
        let result = try await service.stopRecording()

        #expect(result.outcome == .recognizerFailed(.notAuthorized))
        #expect(audioInput.startCount == 0)
    }

    @Test func stopAfterAStartWithoutARecognizerProducesTheFailedOutcome() async throws {
        engine.isAvailable = false

        await #expect(throws: TranscriptionError.notAvailable) {
            try await service.startRecording(language: .english)
        }
        let result = try await service.stopRecording()

        #expect(result.outcome == .recognizerFailed(.notAvailable))
        #expect(audioInput.startCount == 0)
    }

    // MARK: - Stop before start finished

    @Test func stopBeforeStartFinishedReturnsDidNotRun() async throws {
        engine.holdsAuthorization = true
        let service = service
        let start = Task { try await service.startRecording(language: .english) }
        try await waitUntil { engine.hasPendingAuthorization }

        let result = try await service.stopRecording()

        #expect(result.outcome == .recognizerDidNotRun)
        #expect(result.transcription == nil)

        // The start that was overtaken must not bring the microphone up afterwards.
        engine.releaseAuthorization()
        await #expect(throws: TranscriptionError.cancelled) {
            try await start.value
        }
        #expect(engine.liveTasks.isEmpty)
        #expect(audioInput.startCount == 0)
        #expect(!service.isRecording)
    }

    @Test func stopWithoutAnyStartReturnsDidNotRun() async throws {
        let result = try await service.stopRecording()

        #expect(result.outcome == .recognizerDidNotRun)
    }

    // MARK: - File transcription

    @Test func transcribeAudioDataReturnsTheTextOfTheFileTask() async throws {
        engine.fileResult = .success("from the file")
        let audio = Data("saved recording".utf8)

        let result = await service.transcribe(audioData: audio, language: .indonesian)

        #expect(result.transcription == "from the file")
        #expect(result.outcome == .transcribed)
        #expect(result.audioData == audio)
        #expect(result.language == SpeechLanguage.indonesian.rawValue)

        let url = try #require(engine.transcribedFiles.first)
        #expect(engine.fileExistedDuringTranscription)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func transcribeAudioDataReportsAFileTaskErrorAsFailed() async throws {
        engine.fileResult = .failure(Self.recognizerError(code: 1101))

        let result = await service.transcribe(audioData: Data("saved recording".utf8), language: .english)

        #expect(result.transcription == nil)
        #expect(result.outcome == .recognizerFailed(.recognitionFailed))

        let url = try #require(engine.transcribedFiles.first)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func transcribeAudioDataReportsAnEmptyResultAsNoSpeech() async {
        engine.fileResult = .success("")

        let result = await service.transcribe(audioData: Data("saved recording".utf8), language: .english)

        #expect(result.outcome == .noSpeechDetected)
    }

    @Test func transcribeAudioDataWithoutAuthorizationIsFailed() async {
        engine.isAuthorized = false

        let result = await service.transcribe(audioData: Data("saved recording".utf8), language: .english)

        #expect(result.outcome == .recognizerFailed(.notAuthorized))
        #expect(engine.transcribedFiles.isEmpty)
    }

    // MARK: - Cancel

    @Test func cancelRecordingCancelsTheTask() async throws {
        let task = try await startRecording()
        task.emit(.partial("hello"))
        await flushMainQueue()

        service.cancelRecording()

        #expect(task.didCancel)
        #expect(!service.isRecording)
        #expect(service.transcribedText.isEmpty)

        let result = try await service.stopRecording()
        #expect(result.outcome == .recognizerDidNotRun)
    }

    // MARK: - Helpers

    private func startRecording() async throws -> FakeLiveRecognitionTask {
        try await service.startRecording(language: .english)
        return try #require(engine.liveTasks.last)
    }

    /// Lets the events that are already queued for the main queue reach the service.
    private func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            await flushMainQueue()
        }
        Issue.record("The condition was never met")
        throw CancellationError()
    }

    private nonisolated static func recognizerError(code: Int) -> NSError {
        NSError(domain: "kAFAssistantErrorDomain", code: code)
    }
}
