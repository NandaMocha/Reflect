import SwiftUI
import AVFoundation
import Combine
import os

// MARK: - Mode

enum VoiceAudioMode {
    case record(onComplete: (VoiceRecordingInput) -> Void, fromWidget: Bool = false)
    case play(VoiceRecordingInput)
}

// MARK: - View

struct VoiceAudioView: View {
    let mode: VoiceAudioMode
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss

    // Screen state machine
    private enum ScreenState { case idle, recording, playback }
    @State private var screenState: ScreenState = .idle

    // One-time voice-notes intro (record mode only). Its dismissal primes the mic + speech
    // permissions, mirroring the camera-reflection intro → permission hand-off.
    @State private var showIntro = false

    // Recording state
    @State private var waveformLevels: [Float] = []
    @State private var recordDuration: TimeInterval = 0
    @State private var recordTimer: Timer?
    @State private var transcription: String = ""
    @State private var recordingResult: AudioRecordingResult?
    @State private var transcriptTask: Task<Void, Never>?

    // Playback state (shared between post-record replay and play mode)
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?
    @State private var isPlaying: Bool = false
    @State private var currentPlaybackTime: TimeInterval = 0
    @State private var playbackDuration: TimeInterval = 0
    @State private var showTranscription: Bool = false

    // Wrappers (only used in .record mode)
    @State private var audioRecorder = AudioRecorderWrapper()
    @State private var speechRecognizer = SpeechRecognizerWrapper()

    private let selectedLanguage: SpeechLanguage = .indonesian

    // MARK: - Init

    init(mode: VoiceAudioMode, isPresented: Binding<Bool>) {
        self.mode = mode
        self._isPresented = isPresented

        // .play mode: default to showing transcription if one exists and not from widget
        if case .play(let input) = mode {
            self._showTranscription = State(initialValue: !input.fromWidget && input.transcription != nil)
            self._playbackDuration = State(initialValue: input.duration)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimaryLight.ignoresSafeArea()

                VStack(spacing: 0) {
                    waveformSection
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    timerSection
                        .padding(.top, 12)

                    scrubberSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    middleContent

                    Spacer()

                    bottomAction
                        .padding(.bottom, 16)
                }
            }
            // A container of its own, so the identifier names the screen without overriding the
            // identifiers of the controls and transcript states inside it.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voice.recorder")
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: audioRecorder.currentTime) { _, newValue in
                if newValue > 0 { recordDuration = newValue }
            }
            .onChange(of: speechRecognizer.transcription) { _, newValue in
                transcription = newValue
            }
        }
        .onAppear {
            if case .play(let input) = mode {
                waveformLevels = input.waveformSamples
                setupPlayback(data: input.audioData, duration: input.duration)
                screenState = .playback

                // Legacy recordings have no stored samples — analyze the audio on the fly so the
                // waveform shows real amplitude instead of a flat baseline.
                if input.waveformSamples.isEmpty, !input.audioData.isEmpty {
                    Task {
                        let samples = await WaveformSampleLoader.samples(from: input.audioData)
                        if !samples.isEmpty { waveformLevels = samples }
                    }
                }
            }

            // Record mode: show the one-time voice-notes intro before the recorder.
            if case .record = mode,
               !UserDefaults.standard.bool(forKey: Constants.UserDefaults.hasSeenVoiceIntro) {
                showIntro = true
            }
        }
        .onDisappear {
            cleanupPlayback()
        }
        .fullScreenCover(isPresented: $showIntro, onDismiss: handleIntroDismissed) {
            FeatureIntroView(intro: .voice) { showIntro = false }
        }
    }

    /// Persists the "seen" flag when the one-time voice intro is dismissed.
    ///
    /// We deliberately do NOT prime Microphone/Speech permissions here. Firing the system
    /// permission dialogs from the cover's `onDismiss` — while it tears down inside the recorder
    /// sheet — collided with the dismissal and could leave the intro stuck on screen, unable to
    /// close. Both permissions are already requested at point of use instead: the microphone via
    /// `AudioRecorderService.startRecording()` and speech via `SpeechRecognitionService`, both on
    /// the first record tap.
    private func handleIntroDismissed() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.hasSeenVoiceIntro)
    }

    // MARK: - Waveform section

    @ViewBuilder
    private var waveformSection: some View {
        switch screenState {
        case .idle, .recording:
            // Idle draws the recorder's all-silence window: a flat baseline, which reads as
            // "armed, nothing coming in". The previous placeholder was a constant mid-level
            // array, i.e. a fake waveform for audio that didn't exist.
            ReflectWaveform(
                content: .live(samples: audioRecorder.waveformSamples),
                style: .full,
                color: .primaryDefault
            )
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.1), lineWidth: 1))

        case .playback:
            ReflectWaveform(
                content: .playback(samples: waveformLevels, progress: Double(playbackProgress)),
                style: .full
            )
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
            .animation(.linear(duration: 0.1), value: playbackProgress)
        }
    }

    // MARK: - Timer section

    private var timerSection: some View {
        TimerLabel(duration: displayedDuration)
    }

    private var displayedDuration: TimeInterval {
        switch screenState {
        case .idle: return 0
        case .recording: return recordDuration
        case .playback: return currentPlaybackTime
        }
    }

    // MARK: - Scrubber section

    private var scrubberSection: some View {
        ScrubberView(
            elapsed: screenState == .recording ? recordDuration : currentPlaybackTime,
            total: screenState == .recording ? recordDuration : playbackDuration,
            canSeek: screenState == .playback
        ) { newTime in
            seekToTime(newTime)
        }
    }

    // MARK: - Middle content

    @ViewBuilder
    private var middleContent: some View {
        Group {
            switch screenState {
            case .idle:
                Text("Tap to start recording")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)

            case .recording:
                RecordingIndicator()
                    .padding(.vertical, 12)

            case .playback:
                VStack(spacing: 0) {
                    PlaybackControlsRow(
                        isPlaying: isPlaying,
                        onSkipBack: { seekBy(-15) },
                        onTogglePlay: togglePlayback,
                        onSkipForward: { seekBy(15) }
                    )
                    .padding(.vertical, 16)

                    transcriptionSection
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Transcription section

    @ViewBuilder
    private var transcriptionSection: some View {
        switch mode {
        case .record:
            // Post-record replay: the transcript, or the reason there is none
            switch speechRecognizer.status {
            case .idle:
                EmptyView()
            case .transcript(let text):
                TranscriptionCard(text: text)
                    .accessibilityIdentifier("voice.transcript.text")
            case .transcribing:
                TranscriptStatusRow(status: .transcribing)
            case .noSpeech:
                TranscriptStatusRow(status: .noSpeech)
            case .unavailable:
                TranscriptStatusRow(status: .unavailable)
            }

        case .play(let input):
            // Play mode: toggleable transcription
            if let text = input.transcription, !text.isEmpty {
                VStack(spacing: 8) {
                    Button {
                        withAnimation { showTranscription.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.quote")
                                .font(.caption)
                                .foregroundColor(showTranscription ? .primaryDefault : .secondary)
                            Text(showTranscription ? "Hide Transcription" : "Show Transcription")
                                .font(.caption)
                                .foregroundColor(showTranscription ? .primaryDefault : .secondary)
                        }
                    }

                    if showTranscription {
                        TranscriptionCard(text: text)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    // MARK: - Bottom action

    @ViewBuilder
    private var bottomAction: some View {
        switch screenState {
        case .idle:
            RecordButton { Task { await startRecording() } }

        case .recording:
            StopButton { Task { await stopRecording() } }

        case .playback:
            Color.clear.frame(height: 72)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch screenState {
            case .idle, .recording:
                Button("Cancel") {
                    cancelRecording()
                    isPresented = false
                }
            case .playback:
                switch mode {
                case .record:
                    Button("Cancel") {
                        cancelTranscript()
                        cleanupPlayback()
                        isPresented = false
                    }
                case .play:
                    Button("Done") {
                        cleanupPlayback()
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
            }
        }

        if screenState == .playback, case .record = mode {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    completeRecording()
                } label: {
                    Text("Done").fontWeight(.medium)
                }
                .tint(.primaryDefault)
            }
        }
    }

    // MARK: - Recording actions

    @MainActor
    private func startRecording() async {
        do {
            try await audioRecorder.startRecording()
        } catch {
            HapticManager.shared.error()
            return
        }

        // Transcription rides along on top of the audio — it is not the point of the screen,
        // so it must not gate it. Awaiting it here meant speech recognition could take the
        // recording down with it in two different ways: by throwing (permission not granted,
        // locale unsupported), which discarded a perfectly good recording with nothing but an
        // error haptic; or by never returning at all, which left the audio queue running
        // while the UI sat on "Tap to start recording" forever. Start it alongside instead,
        // and treat a missing transcript as a degraded result rather than a failed one.
        speechRecognizer.startRecording(language: selectedLanguage)

        screenState = .recording
        recordDuration = 0
        HapticManager.shared.lightImpact()
    }

    @MainActor
    private func stopRecording() async {
        recordTimer?.invalidate()
        recordTimer = nil

        do {
            let audioResult = try await audioRecorder.stopRecording()
            recordingResult = audioResult

            // Same reasoning as `startRecording`: never let the transcript take the audio
            // down with it. The transcript is worked out on the side, so playback and Done
            // are there right away and a slow or failed recognizer cannot hold them back.
            let language = selectedLanguage
            transcriptTask = Task {
                _ = await speechRecognizer.finishTranscript(audioData: audioResult.data, language: language)
            }

            // Prefer the full-file analysis over the live rolling window: the window only
            // holds the last few seconds, whereas playback needs the whole recording.
            waveformLevels = audioResult.waveformSamples.isEmpty
                ? audioRecorder.waveformSamples
                : audioResult.waveformSamples
            setupPlayback(data: audioResult.data, duration: audioResult.duration)
            screenState = .playback
            HapticManager.shared.success()
        } catch {
            HapticManager.shared.error()
        }
    }

    private func cancelTranscript() {
        transcriptTask?.cancel()
        transcriptTask = nil
        speechRecognizer.cancelRecording()
    }

    private func cancelRecording() {
        audioRecorder.cancelRecording()
        cancelTranscript()
        recordTimer?.invalidate()
        recordTimer = nil
        cleanupPlayback()
    }

    private func completeRecording() {
        guard let result = recordingResult else { return }
        let fromWidget: Bool
        if case .record(_, let fw) = mode { fromWidget = fw } else { fromWidget = false }

        let input = VoiceRecordingInput(
            audioData: result.data,
            transcription: fromWidget ? nil : (transcription.isEmpty ? nil : transcription),
            language: selectedLanguage.localeCode,
            duration: result.duration,
            waveformSamples: result.waveformSamples,
            fromWidget: fromWidget
        )

        // A transcript that is still being worked out is left behind. Save does not wait.
        cancelTranscript()
        cleanupPlayback()
        if case .record(let onComplete, _) = mode {
            onComplete(input)
        }
        isPresented = false
        HapticManager.shared.success()
    }

    // MARK: - Playback actions

    private func setupPlayback(data: Data, duration: TimeInterval) {
        audioPlayer = try? AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        playbackDuration = duration
        currentPlaybackTime = 0
        isPlaying = false
    }

    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            playbackTimer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            startPlaybackTimer()
        }
        HapticManager.shared.lightImpact()
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer else {
                playbackTimer?.invalidate()
                return
            }
            currentPlaybackTime = player.currentTime
            if !player.isPlaying {
                isPlaying = false
                playbackTimer?.invalidate()
            }
        }
    }

    private func seekToTime(_ time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentPlaybackTime = time
        HapticManager.shared.lightImpact()
    }

    private func seekBy(_ seconds: TimeInterval) {
        let newTime = max(0, min(playbackDuration, currentPlaybackTime + seconds))
        seekToTime(newTime)
    }

    private func cleanupPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        currentPlaybackTime = 0
    }

    // MARK: - Computed

    private var playbackProgress: CGFloat {
        guard playbackDuration > 0 else { return 0 }
        return CGFloat(currentPlaybackTime / playbackDuration)
    }
}

// MARK: - Wrapper Classes

@Observable
final class AudioRecorderWrapper {
    var currentTime: TimeInterval = 0

    /// Rolling window of the most recent levels, already in DSWaveformImage's convention
    /// (`0` = loudest, `1` = silence).
    ///
    /// Always exactly `barCount` long: it starts full of silence and scrolls right-to-left,
    /// so the waveform *grows into* the view as you speak. Keeping it a fixed length is what
    /// makes the visualisation honest — a shorter array gets stretched across the full width
    /// by `ReflectWaveform`, which made a half-second of audio look identical in extent to
    /// thirty seconds of it.
    ///
    /// The buffer lives here rather than in the view because a `Float` level that repeats its
    /// previous value — silence, most obviously — doesn't fire `onChange`, so a view-side
    /// buffer stopped scrolling whenever the room went quiet.
    private(set) var waveformSamples: [Float]

    @ObservationIgnored private let barCount: Int
    @ObservationIgnored private let service = AudioRecorderService()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(barCount: Int = 60) {
        self.barCount = barCount
        self.waveformSamples = Self.silence(barCount)

        service.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in self?.appendLevel(level) }
            .store(in: &cancellables)

        service.recordingStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if let duration = state.currentDuration { self?.currentTime = duration }
            }
            .store(in: &cancellables)
    }

    func startRecording() async throws {
        waveformSamples = Self.silence(barCount)
        try await service.startRecording()
    }

    func stopRecording() async throws -> AudioRecordingResult { try await service.stopRecording() }
    func cancelRecording() { service.cancelRecording() }

    /// Shifts the window one bar to the left and drops the new level on the right. The
    /// service publishes normalised loudness (`1` = loudest), which inverts here into the
    /// renderer's convention.
    private func appendLevel(_ level: Float) {
        var next = waveformSamples
        next.removeFirst()
        next.append(max(0, min(1, 1 - level)))
        waveformSamples = next
    }

    private static func silence(_ count: Int) -> [Float] {
        Array(repeating: 1.0, count: count)
    }
}

/// What the transcript area shows once a recording has stopped.
enum TranscriptStatus: Equatable {
    /// Nothing to show: no recording has been stopped yet.
    case idle
    case transcribing
    case transcript(String)
    case noSpeech
    /// The recognizer failed, for example offline without on-device support.
    case unavailable
}

@Observable
final class SpeechRecognizerWrapper {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    /// Lets `finishTranscript` wait for a start that is still running, without waiting forever.
    private final class StartGate {
        private var isOpen = false
        private var waiter: CheckedContinuation<Void, Never>?

        func open() {
            isOpen = true
            waiter?.resume()
            waiter = nil
        }

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }

    /// How long a stop waits for a start that has not finished, for example because the
    /// permission dialog is still up.
    static let startWaitTimeout: TimeInterval = 2

    var transcription: String = ""
    private(set) var status: TranscriptStatus = .idle

    @ObservationIgnored private let service: SpeechRecognitionServiceProtocol
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// True while the live recognizer owns `transcription`. After a stop the text comes
    /// from the results, and a late live update must not overwrite it.
    @ObservationIgnored private var isLive = false
    /// Bumped by every start and cancel, so a transcript that is overtaken is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.nandamochammad.Reflect",
        category: "Speech"
    )

    init(
        service: SpeechRecognitionServiceProtocol = DIContainer.shared.makeSpeechRecognitionService(),
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.service = service
        self.sleep = sleep

        service.transcribedTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, self.isLive else { return }
                self.transcription = text
            }
            .store(in: &cancellables)
    }

    /// Requests Speech Recognition *and* Microphone authorization in one shot (the service asks
    /// for both). Used to prime permissions from the voice-notes intro.
    func requestPermission() async -> Bool { await service.requestPermission() }

    /// Starts the live recognizer without making the caller wait for it. The start is kept,
    /// so a stop that comes right after can wait for it instead of overtaking it.
    func startRecording(language: SpeechLanguage) {
        generation += 1
        isLive = true
        transcription = ""
        status = .idle

        startTask = Task { [service, logger] in
            do {
                try await service.startRecording(language: language)
            } catch {
                // The recording goes on without a live transcript. The stop reports why.
                logger.error("Live transcription did not start: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Stops the live recognizer and settles the transcript: the live text when there is
    /// one, otherwise the file transcription of `audioData`.
    ///
    /// Never throws and never touches the audio: the result always carries `audioData`
    /// as it was passed in.
    @discardableResult
    func finishTranscript(audioData: Data, language: SpeechLanguage) async -> VoiceRecordingResult {
        let myGeneration = generation
        isLive = false
        status = .transcribing

        let live = await stopLive()
        var text = live?.transcription ?? ""
        var outcome = live?.outcome ?? .recognizerDidNotRun

        let liveHasTranscript = outcome == .transcribed && !text.isEmpty
        if !liveHasTranscript, !audioData.isEmpty {
            let fallback = await service.transcribe(audioData: audioData, language: language)
            if let fallbackText = fallback.transcription, !fallbackText.isEmpty {
                text = fallbackText
                outcome = .transcribed
            } else if text.isEmpty {
                outcome = fallback.outcome
            }
            // Otherwise the fallback gave nothing and the live partial text is what is left.
        }

        let result = VoiceRecordingResult(
            audioData: audioData,
            transcription: text.isEmpty ? nil : text,
            language: language.rawValue,
            duration: live?.duration ?? 0,
            outcome: text.isEmpty ? outcome : .transcribed
        )

        // Cancelled, or a new recording started, while the recognizer was working.
        guard myGeneration == generation else { return result }

        transcription = text
        status = Self.status(for: result)
        return result
    }

    func cancelRecording() {
        generation += 1
        isLive = false
        startTask?.cancel()
        startTask = nil
        service.cancelRecording()
        transcription = ""
        status = .idle
    }

    // MARK: - Private Helpers

    private func stopLive() async -> VoiceRecordingResult? {
        if let startTask {
            await waitForStart(startTask)
            self.startTask = nil
        }

        do {
            return try await service.stopRecording()
        } catch {
            logger.error("Live transcription did not stop cleanly: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func waitForStart(_ startTask: Task<Void, Never>) async {
        let gate = StartGate()

        let started = Task {
            await startTask.value
            gate.open()
        }
        let timeout = Task { [sleep] in
            do {
                try await sleep(Self.startWaitTimeout)
            } catch {
                // Cancelled because the start finished first.
                return
            }
            gate.open()
        }
        defer {
            started.cancel()
            timeout.cancel()
        }

        await gate.wait()
    }

    private static func status(for result: VoiceRecordingResult) -> TranscriptStatus {
        if let text = result.transcription, !text.isEmpty {
            return .transcript(text)
        }
        switch result.outcome {
        case .noSpeechDetected:
            return .noSpeech
        case .transcribed, .recognizerFailed, .recognizerDidNotRun:
            return .unavailable
        }
    }
}

// MARK: - Private Subviews

private struct TimerLabel: View {
    let duration: TimeInterval

    private var formatted: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: 64, weight: .light, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(.primary)
            .kerning(-1)
    }
}

private struct ScrubberView: View {
    let elapsed: TimeInterval
    let total: TimeInterval
    let canSeek: Bool
    let onSeek: (TimeInterval) -> Void

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(elapsed / total, 0), 1))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.primaryDefault)
                        .frame(width: geo.size.width * fraction, height: 3)
                    if canSeek || total > 0 {
                        Circle()
                            .fill(Color.primaryDefault)
                            .frame(width: 12, height: 12)
                            .shadow(color: Color.primaryDefault.opacity(0.6), radius: 4)
                            .offset(x: geo.size.width * fraction - 6)
                    }
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    canSeek
                        ? DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let p = max(0, min(1, value.location.x / geo.size.width))
                                onSeek(Double(p) * total)
                            }
                        : nil
                )
            }
            .frame(height: 12)

            HStack {
                Text(formatShort(elapsed)).font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                Spacer()
                Text(formatShort(total)).font(.caption2.monospacedDigit()).foregroundColor(.secondary)
            }
        }
    }

    private func formatShort(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private struct RecordingIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "FF6060"))
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.2 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            Text("Recording...")
                .font(.footnote)
                .foregroundColor(.secondary)
                .tracking(0.5)
        }
        .onAppear { pulse = true }
    }
}

private struct PlaybackControlsRow: View {
    let isPlaying: Bool
    let onSkipBack: () -> Void
    let onTogglePlay: () -> Void
    let onSkipForward: () -> Void

    var body: some View {
        HStack(spacing: 32) {
            Button(action: onSkipBack) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.primaryDefault)
            }

            Button(action: onTogglePlay) {
                ZStack {
                    Circle()
                        .fill(Color.primaryDefault)
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.primaryDefault.opacity(0.4), radius: 12, x: 0, y: 4)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }

            Button(action: onSkipForward) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.primaryDefault)
            }
        }
    }
}

private struct TranscriptionCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRANSCRIPTION")
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color.primaryDefault.opacity(0.8))
                .tracking(0.8)
            Text(text.isEmpty ? "Tap play to listen. Transcription will appear here once recognized." : text)
                .font(.subheadline)
                .foregroundColor(text.isEmpty ? .secondary : .primary)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.primaryDefault.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primaryDefault.opacity(0.2), lineWidth: 1))
    }
}

private struct TranscriptStatusRow: View {
    enum Status {
        case transcribing, noSpeech, unavailable
    }

    let status: Status

    private var title: String {
        switch status {
        case .transcribing: return "Transcribing..."
        case .noSpeech: return "No speech detected"
        case .unavailable: return "Transcript unavailable"
        }
    }

    private var identifier: String {
        switch status {
        case .transcribing: return "voice.transcript.transcribing"
        case .noSpeech: return "voice.transcript.noSpeech"
        case .unavailable: return "voice.transcript.unavailable"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            switch status {
            case .transcribing:
                ProgressView()
            case .noSpeech:
                Image(systemName: "waveform.slash")
                    .accessibilityHidden(true)
            case .unavailable:
                Image(systemName: "exclamationmark.bubble")
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline)
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct StopButton: View {
    let action: () -> Void
    private let coral = Color(hex: "FF6060")

    var body: some View {
        ZStack {
            RippleRing(color: coral, delay: 0)
            RippleRing(color: coral, delay: 1.0)
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(coral)
                        .frame(width: 72, height: 72)
                        .shadow(color: coral.opacity(0.45), radius: 12, x: 0, y: 4)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                }
            }
            .accessibilityLabel("Stop recording")
            .accessibilityIdentifier("voice.stop")
        }
    }
}

private struct RippleRing: View {
    let color: Color
    let delay: Double
    @State private var animating = false

    var body: some View {
        Circle()
            .stroke(color.opacity(animating ? 0 : 0.45), lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(animating ? 2.1 : 1.0)
            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(delay), value: animating)
            .onAppear { animating = true }
    }
}

private struct RecordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.primaryDefault)
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.primaryDefault.opacity(0.4), radius: 14, x: 0, y: 4)
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel("Start recording")
        .accessibilityIdentifier("voice.record")
    }
}

#if DEBUG
// MARK: - UI Testing

/// Stands in for speech recognition when the app is launched with `-uiTestingSpeech <scenario>`,
/// so a UI test can reach every transcript state on a simulator, where the real recognizer
/// cannot be steered. Only the transcript is faked: the audio is still recorded for real.
final class UITestingSpeechRecognitionService: SpeechRecognitionServiceProtocol {
    enum Scenario: String {
        /// The live recognizer heard speech.
        case live
        /// The live recognizer failed and the file fallback heard speech.
        case fallback
        /// Neither heard speech.
        case noSpeech
        /// Both failed, for example offline without on-device support.
        case unavailable
        /// The fallback does not answer, so the screen stays on "Transcribing...".
        case transcribing
    }

    static let launchKey = "uiTestingSpeech"
    static let transcript = "Today I learned that the voice note keeps its audio even when the transcript fails."

    /// The scenario named by the launch arguments, or nil when the app is not under a UI test.
    static var launchScenario: Scenario? {
        UserDefaults.standard.string(forKey: launchKey).flatMap(Scenario.init(rawValue:))
    }

    private let scenario: Scenario

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    var isRecording: Bool { false }
    var transcribedText: String { "" }
    var transcribedTextPublisher: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
    var recordingStatePublisher: AnyPublisher<RecordingState, Never> { Empty().eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { Empty().eraseToAnyPublisher() }

    func requestPermission() async -> Bool { true }
    func startRecording(language: SpeechLanguage) async throws {}
    func cancelRecording() {}

    func stopRecording() async throws -> VoiceRecordingResult {
        switch scenario {
        case .live:
            return result(Data(), text: Self.transcript, outcome: .transcribed, language: .indonesian)
        case .fallback, .unavailable:
            return result(Data(), text: nil, outcome: .recognizerFailed(.recognitionFailed), language: .indonesian)
        case .noSpeech:
            return result(Data(), text: nil, outcome: .noSpeechDetected, language: .indonesian)
        case .transcribing:
            return result(Data(), text: nil, outcome: .recognizerDidNotRun, language: .indonesian)
        }
    }

    func transcribe(audioData: Data, language: SpeechLanguage) async -> VoiceRecordingResult {
        switch scenario {
        case .live, .fallback:
            return result(audioData, text: Self.transcript, outcome: .transcribed, language: language)
        case .noSpeech:
            return result(audioData, text: nil, outcome: .noSpeechDetected, language: language)
        case .unavailable:
            return result(audioData, text: nil, outcome: .recognizerFailed(.notAvailable), language: language)
        case .transcribing:
            // Ends early only when the screen drops the transcript (Done or Cancel).
            try? await Task.sleep(for: .seconds(600))
            return result(audioData, text: nil, outcome: .recognizerFailed(.timedOut), language: language)
        }
    }

    private func result(
        _ audioData: Data,
        text: String?,
        outcome: TranscriptionOutcome,
        language: SpeechLanguage
    ) -> VoiceRecordingResult {
        VoiceRecordingResult(
            audioData: audioData,
            transcription: text,
            language: language.rawValue,
            duration: 0,
            outcome: outcome
        )
    }
}
#endif

// MARK: - Preview

#Preview("Record mode") {
    VoiceAudioView(
        mode: .record(onComplete: { recording in
            print("Recording completed: \(recording.duration)s")
        }),
        isPresented: .constant(true)
    )
}

#Preview("Play mode") {
    VoiceAudioView(
        mode: .play(VoiceRecordingInput(
            audioData: Data(),
            transcription: "This is a sample transcription of the voice note.",
            language: "id-ID",
            duration: 45.5,
            fromWidget: false
        )),
        isPresented: .constant(true)
    )
}
