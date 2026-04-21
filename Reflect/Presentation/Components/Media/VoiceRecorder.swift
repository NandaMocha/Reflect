import SwiftUI
import AVFoundation
import Combine

struct VoiceRecorderView: View {
    @Binding var isPresented: Bool
    var onComplete: (VoiceRecordingInput) -> Void
    var fromWidget: Bool = false  // Track if recording originated from widget

    // Recording state
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var duration: TimeInterval = 0
    @State private var audioLevel: Float = 0
    @State private var audioLevels: [CGFloat] = []
    @State private var transcription = ""
    @State private var recordingResult: AudioRecordingResult?
    @State private var showReplay = false
    @State private var error: Error?
    @State private var timer: Timer?

    // Replay state
    @State private var isPlayingReplay = false
    @State private var replayCurrentTime: TimeInterval = 0
    @State private var replayAudioPlayer: AVAudioPlayer?
    @State private var replayTimer: Timer?

    // Hardcoded to Indonesian
    private let selectedLanguage: SpeechLanguage = .indonesian

    @StateObject private var audioRecorder = AudioRecorderWrapper()
    @StateObject private var speechRecognizer = SpeechRecognizerWrapper()

    private let waveformBarCount = 60
    private let sampleInterval: TimeInterval = 0.05  // Sample every 50ms

    // Default waveform levels for display when no recording
    private var defaultWaveformLevels: [CGFloat] {
        Array(repeating: 0.3, count: waveformBarCount)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    WaveformCard(
                        levels: audioLevels.isEmpty ? defaultWaveformLevels : audioLevels,
                        height: showReplay ? 90 : 110
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    TimerLabel(duration: displayedDuration)
                        .padding(.top, 12)

                    ScrubberView(
                        elapsed: showReplay ? replayCurrentTime : duration,
                        total: showReplay ? duration : duration,
                        canSeek: showReplay
                    ) { newTime in
                        seekToTime(newTime)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Middle content varies by state
                    Group {
                        if isRecording {
                            RecordingIndicator()
                                .padding(.vertical, 12)
                        } else if showReplay {
                            PlaybackControlsRow(
                                isPlaying: isPlayingReplay,
                                onSkipBack: rewindPlayback,
                                onTogglePlay: toggleReplayPlayback,
                                onSkipForward: forwardPlayback
                            )
                            .padding(.vertical, 16)

                            TranscriptionCard(text: transcription)
                                .padding(.horizontal, 20)
                        } else {
                            Text("Tap to start recording")
                                .font(.subheadline)
                                .foregroundColor(Color.white.opacity(0.25))
                                .padding(.vertical, 24)
                        }
                    }

                    Spacer()

                    // Bottom primary action
                    Group {
                        if showReplay {
                            // Done is in the toolbar during replay.
                            Color.clear.frame(height: 72)
                        } else if isRecording {
                            StopButton {
                                Task { await stopRecording() }
                            }
                        } else {
                            RecordButton {
                                Task { await startRecording() }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelRecording()
                        isPresented = false
                    }
                    .tint(.white.opacity(0.85))
                }

                if showReplay {
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
            .onChange(of: audioRecorder.currentTime) { _, newValue in
                if newValue > 0 {
                    duration = newValue
                }
            }
            .onChange(of: audioRecorder.audioLevel) { _, newValue in
                audioLevel = newValue
                if isRecording && !isPaused {
                    let level = CGFloat(newValue)
                    if audioLevels.count >= waveformBarCount {
                        audioLevels.removeFirst()
                    }
                    audioLevels.append(level)
                }
            }
            .onChange(of: speechRecognizer.transcription) { _, newValue in
                transcription = newValue
            }
        }
        .onDisappear {
            cleanupReplay()
        }
    }

    // MARK: - Computed helpers

    /// What the big timer label should show in each state.
    private var displayedDuration: TimeInterval {
        if isRecording { return duration }
        if showReplay { return replayCurrentTime }
        return 0
    }

    // MARK: - Methods

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    @MainActor
    private func startRecording() async {
        do {
            try await audioRecorder.startRecording()
            try await speechRecognizer.startRecording(language: selectedLanguage)

            isRecording = true
            isPaused = false
            duration = 0
            audioLevels = []

            timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { _ in
                duration += sampleInterval
            }

            HapticManager.shared.lightImpact()
        } catch {
            self.error = error
            HapticManager.shared.error()
        }
    }

    @MainActor
    private func stopRecording() async {
        timer?.invalidate()
        timer = nil

        do {
            let audioResult = try await audioRecorder.stopRecording()
            let speechResult = try await speechRecognizer.stopRecording()

            recordingResult = audioResult
            transcription = speechResult.transcription ?? ""
            isRecording = false

            // Prepare for replay
            replayAudioPlayer = try? AVAudioPlayer(data: audioResult.data)
            replayAudioPlayer?.prepareToPlay()
            replayCurrentTime = 0

            showReplay = true
            HapticManager.shared.success()
        } catch {
            self.error = error
            HapticManager.shared.error()
        }
    }

    private func cancelRecording() {
        audioRecorder.cancelRecording()
        speechRecognizer.cancelRecording()
        timer?.invalidate()
        timer = nil
        cleanupReplay()
    }

    private func retakeRecording() {
        recordingResult = nil
        transcription = ""
        duration = 0
        audioLevels = []
        showReplay = false
        isPlayingReplay = false
        replayCurrentTime = 0
        cleanupReplay()
        HapticManager.shared.lightImpact()
    }

    private func completeRecording() {
        guard let result = recordingResult else { return }

        let input = VoiceRecordingInput(
            audioData: result.data,
            transcription: fromWidget ? nil : (transcription.isEmpty ? nil : transcription),
            language: selectedLanguage.localeCode,
            duration: result.duration,
            fromWidget: fromWidget  // Pass flag through
        )

        cleanupReplay()
        onComplete(input)
        isPresented = false
        HapticManager.shared.success()
    }

    // MARK: - Replay Methods

    private func toggleReplayPlayback() {
        guard let player = replayAudioPlayer else { return }

        if isPlayingReplay {
            player.pause()
            isPlayingReplay = false
            replayTimer?.invalidate()
        } else {
            player.play()
            isPlayingReplay = true
            startReplayTimer()
        }
        HapticManager.shared.lightImpact()
    }

    private func startReplayTimer() {
        replayTimer?.invalidate()
        replayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = replayAudioPlayer else {
                replayTimer?.invalidate()
                return
            }

            replayCurrentTime = player.currentTime

            if !player.isPlaying {
                isPlayingReplay = false
                replayTimer?.invalidate()
            }
        }
    }

    private func seekToTime(_ time: TimeInterval) {
        replayAudioPlayer?.currentTime = time
        replayCurrentTime = time
        HapticManager.shared.lightImpact()
    }

    private func rewindPlayback() {
        let newTime = max(0, replayCurrentTime - 15)
        seekToTime(newTime)
    }

    private func forwardPlayback() {
        let newTime = min(duration, replayCurrentTime + 15)
        seekToTime(newTime)
    }

    private func cleanupReplay() {
        replayAudioPlayer?.stop()
        replayAudioPlayer = nil
        replayTimer?.invalidate()
        replayTimer = nil
        isPlayingReplay = false
        replayCurrentTime = 0
    }
}

// MARK: - Wrapper Classes

class AudioRecorderWrapper: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private let service = AudioRecorderService()

    func startRecording() async throws {
        try await service.startRecording()
    }

    func stopRecording() async throws -> AudioRecordingResult {
        try await service.stopRecording()
    }

    func cancelRecording() {
        service.cancelRecording()
    }
}

class SpeechRecognizerWrapper: ObservableObject {
    @Published var transcription: String = ""

    private let service = SpeechRecognitionService()

    func startRecording(language: SpeechLanguage) async throws {
        try await service.startRecording(language: language)
    }

    func stopRecording() async throws -> VoiceRecordingResult {
        try await service.stopRecording()
    }

    func cancelRecording() {
        service.cancelRecording()
    }
}

// MARK: - Subviews (private to this file)

/// Bordered rounded card wrapping a mirrored waveform.
private struct WaveformCard: View {
    let levels: [CGFloat]
    let height: CGFloat

    var body: some View {
        AudioWaveform.mirror(audioLevels: levels, color: .primaryDefault, height: height)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

/// Big monospaced timer in `M:SS` form. Uses system-monospaced design rather than bundling
/// DM Mono — the design's intent is a clean monospaced look, which the system font delivers.
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
            .foregroundColor(.white)
            .kerning(-1)
    }
}

/// Track + fill + thumb + timestamps. Tap-or-drag to seek when `canSeek` is true.
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
                        .fill(Color.white.opacity(0.1))
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
                Text(formatShort(elapsed))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.35))
                Spacer()
                Text(formatShort(total))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.35))
            }
        }
    }

    private func formatShort(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Blinking red dot + "Recording…" caption.
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
                .foregroundColor(Color.white.opacity(0.5))
                .tracking(0.5)
        }
        .onAppear { pulse = true }
    }
}

/// Skip-15-back · Play/Pause · Skip-15-forward — arranged per the design.
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
                        .offset(x: isPlaying ? 0 : 2)  // optical centering for the play triangle
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

/// Green-tinted transcription card shown in replay state.
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
                .foregroundColor(Color.white.opacity(text.isEmpty ? 0.45 : 0.8))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.primaryDefault.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primaryDefault.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Coral stop button with two expanding ripple rings.
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
            .animation(
                .easeOut(duration: 2).repeatForever(autoreverses: false).delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

/// Primary-green start-record button with a white mic icon.
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

#Preview {
    VoiceRecorderView(isPresented: .constant(true)) { recording in
        print("Recording completed: \(recording.duration)s")
    }
}
