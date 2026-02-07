import SwiftUI
import AVFoundation

struct VoicePlayerPopup: View {
    let voiceRecording: VoiceRecordingInput
    @Environment(\.dismiss) var dismiss

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var showTranscription = true
    @State private var audioPlayer: AVAudioPlayer?
    @State private var progressTimer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: Constants.Spacing.xl) {
                // Header
                header

                // Waveform visualization
                waveformView

                // Duration
                Text(formatDuration(isPlaying ? currentTime : voiceRecording.duration))
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundColor(.primary)

                // Progress bar with scrubbing
                progressBar

                // Playback controls
                playbackControls

                // Transcription (scrollable)
                if showTranscription, let transcription = voiceRecording.transcription, !transcription.isEmpty {
                    transcriptionView(transcription)
                }

                Spacer()
            }
            .padding(Constants.Spacing.lg)
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        stopPlayback()
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            currentTime = 0
            setupAudioPlayer()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Components

    private var header: some View {
        HStack {
            Text("Recording")
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            if voiceRecording.transcription != nil {
                Button {
                    withAnimation {
                        showTranscription.toggle()
                    }
                } label: {
                    Image(systemName: "text.quote")
                        .font(.callout)
                        .foregroundColor(showTranscription ? .primaryDefault : .secondary)
                }
            }
        }
    }

    private var waveformView: some View {
        // Generate static waveform for visualization
        AudioWaveform(
            audioLevels: generateWaveformLevels(),
            isAnimating: false,
            color: .primaryDefault
        )
        .frame(height: 80)
        .padding(.horizontal, Constants.Spacing.md)
    }

    private var progressBar: some View {
        VStack(spacing: Constants.Spacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color.primaryDefault)
                        .frame(width: geometry.size.width * progress, height: 6)

                    // Progress knob
                    Circle()
                        .fill(Color.primaryDefault)
                        .frame(width: 14, height: 14)
                        .offset(x: geometry.size.width * progress - 7)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newTime = Double(max(0, min(1, value.location.x / geometry.size.width))) * voiceRecording.duration
                            seekToTime(newTime)
                        }
                )
            }
            .frame(height: 6)

            HStack {
                Text(formatDuration(currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)

                Spacer()

                Text(formatDuration(voiceRecording.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Constants.Spacing.md)
    }

    private var playbackControls: some View {
        HStack(spacing: Constants.Spacing.xl) {
            // Rewind 15 seconds
            Button {
                seekBy(-15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
                    .foregroundColor(.primaryDefault)
            }

            // Play/Pause button
            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.primaryDefault)
                        .frame(width: 64, height: 64)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }

            // Forward 15 seconds
            Button {
                seekBy(15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
                    .foregroundColor(.primaryDefault)
            }
        }
    }

    private func transcriptionView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text("Transcription")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            .padding()
            .glassCard()
        }
    }

    // MARK: - Computed Properties

    private var progress: CGFloat {
        guard voiceRecording.duration > 0 else { return 0 }
        return CGFloat(currentTime / voiceRecording.duration)
    }

    // MARK: - Methods

    private func setupAudioPlayer() {
        if audioPlayer == nil {
            audioPlayer = try? AVAudioPlayer(data: voiceRecording.audioData)
            audioPlayer?.prepareToPlay()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func togglePlayback() {
        guard let player = audioPlayer else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
            progressTimer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            startProgressTimer()
        }
        HapticManager.shared.lightImpact()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer else {
                progressTimer?.invalidate()
                return
            }

            currentTime = player.currentTime

            if !player.isPlaying {
                isPlaying = false
                progressTimer?.invalidate()
            }
        }
    }

    private func seekToTime(_ time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
        HapticManager.shared.lightImpact()
    }

    private func seekBy(_ seconds: TimeInterval) {
        let newTime = max(0, min(voiceRecording.duration, currentTime + seconds))
        seekToTime(newTime)
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Generate synthetic waveform levels for visualization
    private func generateWaveformLevels() -> [CGFloat] {
        let count = 60
        var levels: [CGFloat] = []

        // Create a natural-looking waveform pattern
        for i in 0..<count {
            let normalizedPos = CGFloat(i) / CGFloat(count)
            // Use sine waves combined with noise for natural look
            let baseWave = sin(normalizedPos * .pi * 4) * 0.3 + 0.5
            let variation = sin(normalizedPos * .pi * 10) * 0.2
            let noise = CGFloat.random(in: -0.1...0.1)
            let level = max(0.1, min(1.0, baseWave + variation + noise))
            levels.append(level)
        }

        return levels
    }
}

#Preview {
    let recording = VoiceRecordingInput(
        audioData: Data(),
        transcription: "This is a sample transcription of the voice note. It can contain multiple sentences that describe what the user said during the recording.",
        language: "id-ID",
        duration: 45.5
    )

    VoicePlayerPopup(voiceRecording: recording)
}
