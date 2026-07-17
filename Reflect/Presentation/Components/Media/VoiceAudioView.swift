import SwiftUI
import AVFoundation
import Combine

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

    // Recording state
    @State private var waveformLevels: [Float] = []
    @State private var recordDuration: TimeInterval = 0
    @State private var recordTimer: Timer?
    @State private var transcription: String = ""
    @State private var recordingResult: AudioRecordingResult?

    // Playback state (shared between post-record replay and play mode)
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?
    @State private var isPlaying: Bool = false
    @State private var currentPlaybackTime: TimeInterval = 0
    @State private var playbackDuration: TimeInterval = 0
    @State private var showTranscription: Bool = false

    // Wrappers (only used in .record mode)
    @StateObject private var audioRecorder = AudioRecorderWrapper()
    @StateObject private var speechRecognizer = SpeechRecognizerWrapper()

    private let selectedLanguage: SpeechLanguage = .indonesian
    private let waveformBarCount = 60
    private let sampleInterval: TimeInterval = 0.05

    private var defaultWaveformLevels: [Float] {
        Array(repeating: Float(0.65), count: waveformBarCount)
    }

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
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: audioRecorder.currentTime) { _, newValue in
                if newValue > 0 { recordDuration = newValue }
            }
            .onChange(of: audioRecorder.audioLevel) { _, newValue in
                if screenState == .recording {
                    let level = max(0, min(1, 1 - newValue))
                    if waveformLevels.count >= waveformBarCount { waveformLevels.removeFirst() }
                    waveformLevels.append(level)
                }
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
        }
        .onDisappear {
            cleanupPlayback()
        }
    }

    // MARK: - Waveform section

    @ViewBuilder
    private var waveformSection: some View {
        switch screenState {
        case .idle, .recording:
            ReflectWaveform(
                content: .live(samples: waveformLevels.isEmpty ? defaultWaveformLevels : waveformLevels),
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
            // Post-record replay: show transcription card if text exists
            if !transcription.isEmpty {
                TranscriptionCard(text: transcription)
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
            try await speechRecognizer.startRecording(language: selectedLanguage)
            screenState = .recording
            recordDuration = 0
            waveformLevels = []
            HapticManager.shared.lightImpact()
        } catch {
            HapticManager.shared.error()
        }
    }

    @MainActor
    private func stopRecording() async {
        recordTimer?.invalidate()
        recordTimer = nil

        do {
            let audioResult = try await audioRecorder.stopRecording()
            let speechResult = try await speechRecognizer.stopRecording()

            recordingResult = audioResult
            transcription = speechResult.transcription ?? ""

            waveformLevels = audioResult.waveformSamples.isEmpty ? waveformLevels : audioResult.waveformSamples
            setupPlayback(data: audioResult.data, duration: audioResult.duration)
            screenState = .playback
            HapticManager.shared.success()
        } catch {
            HapticManager.shared.error()
        }
    }

    private func cancelRecording() {
        audioRecorder.cancelRecording()
        speechRecognizer.cancelRecording()
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

class AudioRecorderWrapper: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private let service = AudioRecorderService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        service.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in self?.audioLevel = level }
            .store(in: &cancellables)

        service.recordingStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if let duration = state.currentDuration { self?.currentTime = duration }
            }
            .store(in: &cancellables)
    }

    func startRecording() async throws { try await service.startRecording() }
    func stopRecording() async throws -> AudioRecordingResult { try await service.stopRecording() }
    func cancelRecording() { service.cancelRecording() }
}

class SpeechRecognizerWrapper: ObservableObject {
    @Published var transcription: String = ""

    private let service = SpeechRecognitionService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        service.transcribedTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.transcription = text }
            .store(in: &cancellables)
    }

    func startRecording(language: SpeechLanguage) async throws { try await service.startRecording(language: language) }
    func stopRecording() async throws -> VoiceRecordingResult { try await service.stopRecording() }
    func cancelRecording() { service.cancelRecording() }
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
    }
}

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
