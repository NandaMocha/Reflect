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
            VStack(spacing: Constants.Spacing.lg) {
                Spacer()

                // Unified recording UI - same layout for recording and playback
                unifiedRecordingView

                Spacer()

                controlButtons
            }
            .padding(Constants.Spacing.lg)
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelRecording()
                        isPresented = false
                    }
                }

                // Save button in toolbar (visible only in replay mode)
                if showReplay {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            completeRecording()
                        } label: {
                            Text("Save")
                                .fontWeight(.medium)
                        }
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
                // Capture audio levels for waveform visualization
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

    // MARK: - Unified Recording View

    private var unifiedRecordingView: some View {
        VStack(spacing: Constants.Spacing.xl) {
            // Waveform (live during recording, progress during playback)
            AudioWaveform.progress(
                audioLevels: audioLevels.isEmpty ? defaultWaveformLevels : audioLevels,
                progress: showReplay ? replayProgress : 0
            )
            .frame(height: 80)
            .animation(.linear(duration: 0.1), value: replayProgress)

            // Timer display
            Text(formatDuration(isRecording ? duration : (showReplay && isPlayingReplay ? replayCurrentTime : duration)))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.primary)

            // Progress bar (visible during recording and after)
            if duration > 0 {
                progressBarView
            }

            // Playback controls (visible during recording and after)
            if duration > 0 || isRecording {
                playbackControlsView
            }

            // Status text (only when idle)
            if !isRecording && !isPlayingReplay && duration == 0 {
                Text("Tap to Record")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Progress Bar View

    private var progressBarView: some View {
        VStack(spacing: Constants.Spacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color.primaryDefault)
                        .frame(width: geometry.size.width * currentProgress, height: 6)

                    // Progress knob (only during playback)
                    if showReplay {
                        Circle()
                            .fill(Color.primaryDefault)
                            .frame(width: 14, height: 14)
                            .offset(x: geometry.size.width * currentProgress - 7)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    showReplay ? DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newTime = Double(max(0, min(1, value.location.x / geometry.size.width))) * duration
                            seekToTime(newTime)
                        }
                    : nil
                )
            }
            .frame(height: 6)

            HStack {
                Text(formatDuration(showReplay ? replayCurrentTime : 0))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)

                Spacer()

                Text(formatDuration(duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Constants.Spacing.md)
    }

    // MARK: - Playback Controls View

    private var playbackControlsView: some View {
        HStack(spacing: Constants.Spacing.xl) {
            if showReplay {
                // Rewind 15 seconds
                Button {
                    rewindPlayback()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .foregroundColor(.primaryDefault)
                }
                
                // Retake button
                Button {
                    retakeRecording()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                // Play/Pause button
                Button {
                    toggleReplayPlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primaryDefault)
                            .frame(width: 56, height: 56)

                        Image(systemName: isPlayingReplay ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }

                // Forward 15 seconds
                Button {
                    forwardPlayback()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .foregroundColor(.primaryDefault)
                }
            } else {
                // During recording - show centered mic/stop indicator
                Spacer()

                if isRecording {
                    // Recording indicator
                    Text("● Recording...")
                        .font(.subheadline)
                        .foregroundColor(.error)
                }

                Spacer()
            }
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: Constants.Spacing.xl) {
            if showReplay {
                // Empty - controls are now in playbackControlsView
                // Save is in toolbar
                Spacer()
            } else {
                // Main record/stop button
                Button {
                    Task {
                        if isRecording {
                            await stopRecording()
                        } else {
                            await startRecording()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.error : Color.primaryDefault)
                            .frame(width: 72, height: 72)

                        if isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }
        }
        .padding(.bottom, Constants.Spacing.lg)
    }

    // MARK: - Computed Properties

    private var currentProgress: CGFloat {
        if showReplay {
            return replayProgress
        } else {
            return duration > 0 ? 1.0 : 0
        }
    }

    private var replayProgress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(replayCurrentTime / duration)
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

#Preview {
    VoiceRecorderView(isPresented: .constant(true)) { recording in
        print("Recording completed: \(recording.duration)s")
    }
}
