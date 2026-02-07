import SwiftUI
import AVFoundation
import Combine

struct VoiceRecorderView: View {
    @Binding var isPresented: Bool
    var onComplete: (VoiceRecordingInput) -> Void

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

    var body: some View {
        NavigationStack {
            VStack(spacing: Constants.Spacing.lg) {
                Spacer()

                if showReplay {
                    replayView
                } else {
                    recordingView
                }

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

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: Constants.Spacing.xl) {
            // Recording indicator with waveform
            VStack(spacing: Constants.Spacing.md) {
                if isRecording {
                    // Waveform visualization during recording
                    AudioWaveform.live(audioLevels: $audioLevels)
                        .frame(height: 80)

                    // Duration
                    Text(formatDuration(duration))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    // Microphone icon when not recording
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 120, height: 120)

                        Image(systemName: "mic")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Status text
            Text(statusText)
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Replay View

    private var replayView: some View {
        VStack(spacing: Constants.Spacing.xl) {
            // Waveform visualization (static)
            AudioWaveform.playback(
                audioLevels: audioLevels.isEmpty ? [CGFloat](repeating: 0.3, count: waveformBarCount) : audioLevels
            )
            .frame(height: 80)

            // Duration
            Text(formatDuration(isPlayingReplay ? replayCurrentTime : duration))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.primary)

            // Status
            Text(isPlayingReplay ? "Playing..." : "Review Recording")
                .font(.headline)
                .foregroundColor(.secondary)

            // Progress bar
            VStack(spacing: Constants.Spacing.xs) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.primaryDefault)
                            .frame(width: geometry.size.width * replayProgress, height: 6)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newTime = Double(value.location.x / geometry.size.width) * duration
                                replayCurrentTime = max(0, min(duration, newTime))
                                replayAudioPlayer?.currentTime = replayCurrentTime
                            }
                    )
                }
                .frame(height: 6)

                HStack {
                    Text(formatDuration(replayCurrentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(formatDuration(duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, Constants.Spacing.md)

            // Playback controls
            HStack(spacing: Constants.Spacing.xl) {
                Button {
                    rewindPlayback()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .foregroundColor(.primaryDefault)
                }

                Button {
                    toggleReplayPlayback()
                } label: {
                    Image(systemName: isPlayingReplay ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.primaryDefault)
                        .clipShape(Circle())
                }

                Button {
                    forwardPlayback()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .foregroundColor(.primaryDefault)
                }
            }
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: Constants.Spacing.xl) {
            if showReplay {
                // Retake button
                Button {
                    retakeRecording()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Constants.Spacing.lg)
                        .padding(.vertical, Constants.Spacing.md)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(Constants.CornerRadius.medium)
                }

                // Save button
                Button {
                    completeRecording()
                } label: {
                    Label("Save", systemImage: "checkmark")
                        .font(.body.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, Constants.Spacing.lg)
                        .padding(.vertical, Constants.Spacing.md)
                        .background(Color.primaryDefault)
                        .cornerRadius(Constants.CornerRadius.medium)
                }
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

    private var statusText: String {
        if showReplay {
            return "Review & Save"
        } else if isRecording {
            return "Recording..."
        } else if isPaused {
            return "Paused"
        } else {
            return "Tap to Record"
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
            transcription: transcription.isEmpty ? nil : transcription,
            language: selectedLanguage.localeCode,
            duration: result.duration
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

    private func rewindPlayback() {
        let newTime = max(0, replayCurrentTime - 15)
        replayCurrentTime = newTime
        replayAudioPlayer?.currentTime = newTime
        HapticManager.shared.lightImpact()
    }

    private func forwardPlayback() {
        let newTime = min(duration, replayCurrentTime + 15)
        replayCurrentTime = newTime
        replayAudioPlayer?.currentTime = newTime
        HapticManager.shared.lightImpact()
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
