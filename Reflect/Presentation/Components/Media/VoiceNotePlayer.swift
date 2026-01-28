import SwiftUI
import AVFoundation

struct VoiceNotePlayer: View {
    let voiceRecording: VoiceRecording

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var showTranscription = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var progressTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.primaryDefault)

                Text("Voice Note")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(formatDuration(voiceRecording.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // Player Controls
            HStack(spacing: Constants.Spacing.md) {
                // Play/Pause Button
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.primaryDefault)
                }

                // Progress
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 4)

                            // Progress track
                            Capsule()
                                .fill(Color.primaryDefault)
                                .frame(width: geometry.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)

                    // Time labels
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
            }

            // Transcription (if available)
            if let transcription = voiceRecording.transcription, !transcription.isEmpty {
                DisclosureGroup(
                    isExpanded: $showTranscription,
                    content: {
                        Text(transcription)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.top, Constants.Spacing.xs)
                    },
                    label: {
                        HStack {
                            Image(systemName: "text.quote")
                                .font(.caption)
                            Text("Transcription")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.secondary)
                    }
                )
            }
        }
        .padding(Constants.Spacing.md)
        .glassCard()
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Computed Properties

    private var progress: CGFloat {
        guard voiceRecording.duration > 0 else { return 0 }
        return CGFloat(currentTime / voiceRecording.duration)
    }

    // MARK: - Methods

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let audioData = voiceRecording.audioData else { return }

        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = AudioPlayerDelegateHandler(onFinished: {
                stopPlayback()
            })
            audioPlayer?.play()
            isPlaying = true

            // Start timer for progress updates
            startProgressTimer()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if let player = audioPlayer, player.isPlaying {
                currentTime = player.currentTime
            } else {
                timer.invalidate()
                progressTimer = nil
            }
        }
    }
}

// MARK: - Audio Player Delegate Handler

private class AudioPlayerDelegateHandler: NSObject, AVAudioPlayerDelegate {
    let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished()
    }
}

#Preview {
    let recording = VoiceRecording(
        audioData: nil,
        transcription: "This is a sample transcription of the voice note. It can contain multiple sentences.",
        language: "en-US",
        duration: 45
    )

    VoiceNotePlayer(voiceRecording: recording)
        .padding()
}
