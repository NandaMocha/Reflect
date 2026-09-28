import Foundation
import Combine
import Testing
@testable import Reflect

/// Stands in for the whole speech service, so the wrapper's own rules can be tested: which
/// text wins, when the file fallback runs, and that the audio is never touched.
final class FakeSpeechRecognitionService: SpeechRecognitionServiceProtocol {
    var liveResult: Result<VoiceRecordingResult, any Error> = .success(
        VoiceRecordingResult(audioData: Data(), transcription: nil, language: "en-US", duration: 0)
    )
    var fallbackOutcome: TranscriptionOutcome = .noSpeechDetected
    var fallbackText: String?
    /// When true, `startRecording` does not return until `releaseStart()`.
    var holdsStart = false
    /// When true, `transcribe` does not return until `releaseFallback()`.
    var holdsFallback = false

    private(set) var calls: [String] = []
    private(set) var transcribedAudio: [Data] = []
    private(set) var transcribedLanguages: [Constants.SpeechLanguage] = []

    private var pendingStarts: [CheckedContinuation<Void, Never>] = []
    private var pendingFallbacks: [CheckedContinuation<Void, Never>] = []
    private let textSubject = CurrentValueSubject<String, Never>("")

    var isRecording = false
    var transcribedText: String { textSubject.value }
    var transcribedTextPublisher: AnyPublisher<String, Never> { textSubject.eraseToAnyPublisher() }
    var recordingStatePublisher: AnyPublisher<RecordingState, Never> {
        Just(RecordingState.idle).eraseToAnyPublisher()
    }
    var audioLevelPublisher: AnyPublisher<Float, Never> { Empty().eraseToAnyPublisher() }

    func sendLiveText(_ text: String) { textSubject.send(text) }

    func releaseStart() {
        holdsStart = false
        let pending = pendingStarts
        pendingStarts = []
        pending.forEach { $0.resume() }
    }

    func releaseFallback() {
        holdsFallback = false
        let pending = pendingFallbacks
        pendingFallbacks = []
        pending.forEach { $0.resume() }
    }

    func requestPermission() async -> Bool { true }

    func startRecording(language: Constants.SpeechLanguage) async throws {
        calls.append("start")
        if holdsStart {
            await withCheckedContinuation { pendingStarts.append($0) }
        }
        calls.append("started")
        isRecording = true
    }

    func stopRecording() async throws -> VoiceRecordingResult {
        calls.append("stop")
        isRecording = false
        return try liveResult.get()
    }

    func cancelRecording() {
        calls.append("cancel")
        isRecording = false
    }

    func transcribe(audioData: Data, language: Constants.SpeechLanguage) async -> VoiceRecordingResult {
        calls.append("transcribe")
        transcribedAudio.append(audioData)
        transcribedLanguages.append(language)
        if holdsFallback {
            await withCheckedContinuation { pendingFallbacks.append($0) }
        }
        return VoiceRecordingResult(
            audioData: audioData,
            transcription: fallbackText,
            language: language.rawValue,
            duration: 0,
            outcome: fallbackOutcome
        )
    }
}

@MainActor
struct SpeechRecognizerWrapperTests {
    static let audio = Data("the recording".utf8)

    let service = FakeSpeechRecognitionService()
    let sleep = FakeSleep()
    let wrapper: SpeechRecognizerWrapper

    init() {
        let sleep = sleep
        wrapper = SpeechRecognizerWrapper(service: service, sleep: { try await sleep.sleep($0) })
    }

    // MARK: - Live text

    @Test func liveTextIsUsedWhenPresent() async {
        service.liveResult = .success(Self.live("live text", .transcribed))

        let result = await wrapper.finishTranscript(audioData: Self.audio, language: .indonesian)

        #expect(result.transcription == "live text")
        #expect(result.outcome == .transcribed)
        #expect(result.audioData == Self.audio)
        #expect(wrapper.transcription == "live text")
        #expect(wrapper.status == .transcript("live text"))
        #expect(!service.calls.contains("transcribe"))
    }

    // MARK: - Fallback

    @Test(arguments: [
        TranscriptionOutcome.noSpeechDetected,
        .recognizerFailed(.recognitionFailed),
        .recognizerFailed(.timedOut),
        .recognizerDidNotRun
    ])
    func fallbackTextIsUsedWhenLiveHasNoTranscript(liveOutcome: TranscriptionOutcome) async {
        service.liveResult = .success(Self.live(nil, liveOutcome))
        service.fallbackText = "from the file"
        service.fallbackOutcome = .transcribed

        let result = await wrapper.finishTranscript(audioData: Self.audio, language: .indonesian)

        #expect(result.transcription == "from the file")
        #expect(result.outcome == .transcribed)
        #expect(result.audioData == Self.audio)
        #expect(wrapper.status == .transcript("from the file"))
        #expect(service.transcribedAudio == [Self.audio])
        #expect(service.transcribedLanguages == [.indonesian])
    }

    @Test func fallbackRunsWhenTheLiveStopThrows() async {
        service.liveResult = .failure(TranscriptionError.recognitionFailed)
        service.fallbackText = "from the file"
        service.fallbackOutcome = .transcribed

        let result = await wrapper.finishTranscript(audioData: Self.audio, language: .english)

        #expect(result.transcription == "from the file")
        #expect(result.audioData == Self.audio)
        #expect(wrapper.status == .transcript("from the file"))
    }

    @Test func fallbackTextWinsOverALivePartial() async {
        service.liveResult = .success(Self.live("live part", .recognizerFailed(.recognitionFailed)))
        service.fallbackText = "the whole sentence from the file"
        service.fallbackOutcome = .transcribed

        let result = await wrapper.finishTranscript(audioData: Self.audio, language: .english)

        #expect(result.transcription == "the whole sentence from the file")
        #expect(wrapper.status == .transcript("the whole sentence from the file"))
    }

    @Test func livePartialIsUsedWhenTheFallbackAlsoFails() async {
        service.liveResult = .success(Self.live("live part", .recognizerFailed(.recognitionFailed)))
        service.fallbackOutcome = .recognizerFailed(.timedOut)

        let result = await wrapper.finishTranscript(audioData: Self.audio, language: .english)

        #expect(result.transcription == "live part")
        #expect(result.outcome == .transcribed)
        #expect(result.audioData == Self.audio)
        #expect(wrapper.status == .transcript("live part"))
    }

    @Test func failedFallbackYieldsUnavailable() async {
        service.liveResult = .success(Self.live(nil, .recognizerFailed(.notAvailable)))
        service.fallbackOutcome = .recognizerFailed(.notAvailable)

        let result = await wrapper.finishTranscript(audioData: Self.audio, language: .english)

        #expect(result.transcription == nil)
        #expect(result.outcome == .recognizerFailed(.notAvailable))
        #expect(result.audioData == Self.audio)
        #expect(wrapper.transcription.isEmpty)
        #expect(wrapper.status == .unavailable)
    }

    @Test func fallbackWithoutSpeechYieldsNoSpeech() async {
        service.liveResult = .success(Self.live(nil, .recognizerDidNotRun))
        service.fallbackOutcome = .noSpeechDetected

        let result = await wrapper.finishTranscript(audioData: Self.audio, language: .english)

        #expect(result.transcription == nil)
        #expect(result.outcome == .noSpeechDetected)
        #expect(result.audioData == Self.audio)
        #expect(wrapper.status == .noSpeech)
    }

    @Test func statusIsTranscribingWhileTheFallbackRuns() async throws {
        service.liveResult = .success(Self.live(nil, .recognizerDidNotRun))
        service.fallbackText = "from the file"
        service.fallbackOutcome = .transcribed
        service.holdsFallback = true

        async let finished = wrapper.finishTranscript(audioData: Self.audio, language: .english)
        try await waitUntil { service.calls.contains("transcribe") }

        #expect(wrapper.status == .transcribing)

        service.releaseFallback()
        let result = await finished

        #expect(result.audioData == Self.audio)
        #expect(wrapper.status == .transcript("from the file"))
    }

    @Test func lateLiveTextDoesNotOverwriteTheSettledTranscript() async throws {
        service.liveResult = .success(Self.live(nil, .noSpeechDetected))
        service.fallbackText = "from the file"
        service.fallbackOutcome = .transcribed

        _ = await wrapper.finishTranscript(audioData: Self.audio, language: .english)
        service.sendLiveText("")
        await flushMainQueue()

        #expect(wrapper.transcription == "from the file")
    }

    // MARK: - Start / stop race

    @Test func stopWaitsForAStartThatIsStillRunning() async throws {
        service.holdsStart = true
        service.liveResult = .success(Self.live("live text", .transcribed))

        wrapper.startRecording(language: .english)
        try await waitUntil { service.calls.contains("start") }

        async let finished = wrapper.finishTranscript(audioData: Self.audio, language: .english)
        try await waitUntil { !sleep.requested.isEmpty }
        #expect(!service.calls.contains("stop"))

        service.releaseStart()
        let result = await finished
        sleep.fire()

        #expect(service.calls == ["start", "started", "stop"])
        #expect(result.transcription == "live text")
    }

    @Test func stopDoesNotWaitForeverForAStartThatNeverFinishes() async throws {
        service.holdsStart = true
        service.liveResult = .success(Self.live(nil, .recognizerDidNotRun))
        service.fallbackText = "from the file"
        service.fallbackOutcome = .transcribed

        wrapper.startRecording(language: .english)
        try await waitUntil { service.calls.contains("start") }

        async let finished = wrapper.finishTranscript(audioData: Self.audio, language: .english)
        try await waitUntil { !sleep.requested.isEmpty }
        #expect(sleep.requested.first == SpeechRecognizerWrapper.startWaitTimeout)
        sleep.fire()

        let result = await finished

        #expect(service.calls == ["start", "stop", "transcribe"])
        #expect(result.transcription == "from the file")
        #expect(result.audioData == Self.audio)
        service.releaseStart()
    }

    // MARK: - Cancel

    @Test func cancelDropsATranscriptThatIsStillBeingWorkedOut() async throws {
        service.liveResult = .success(Self.live(nil, .recognizerDidNotRun))
        service.fallbackText = "from the file"
        service.fallbackOutcome = .transcribed
        service.holdsFallback = true

        async let finished = wrapper.finishTranscript(audioData: Self.audio, language: .english)
        try await waitUntil { service.calls.contains("transcribe") }

        wrapper.cancelRecording()
        service.releaseFallback()
        let result = await finished

        #expect(result.audioData == Self.audio)
        #expect(wrapper.transcription.isEmpty)
        #expect(wrapper.status == .idle)
    }

    // MARK: - Helpers

    private static func live(_ text: String?, _ outcome: TranscriptionOutcome) -> VoiceRecordingResult {
        VoiceRecordingResult(
            audioData: Data("what the speech engine recorded".utf8),
            transcription: text,
            language: "en-US",
            duration: 4,
            outcome: outcome
        )
    }

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
}
