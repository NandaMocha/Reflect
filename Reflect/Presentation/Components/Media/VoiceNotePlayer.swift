import SwiftUI
import AVFoundation

struct VoiceNotePlayer: View {
    let voiceRecording: VoiceRecording

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var progressTimer: Timer?
    @State private var showTranscriptionPopup = false

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            // Play/Pause Button
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.primaryDefault)
                    .clipShape(Circle())
            }

            // Progress Bar & Time
            VStack(spacing: 2) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 3)

                        Capsule()
                            .fill(Color.primaryDefault)
                            .frame(width: geometry.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)

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

            // Transcription Menu (if available)
            if voiceRecording.hasTranscription {
                Button(action: { showTranscriptionPopup = true }) {
                    Image(systemName: "text.quote")
                        .font(.caption)
                        .foregroundColor(.primaryDefault)
                }
            }
        }
        .padding(.vertical, Constants.Spacing.xs)
        .padding(.horizontal, Constants.Spacing.sm)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(Constants.CornerRadius.medium)
        .sheet(isPresented: $showTranscriptionPopup) {
            TranscriptionPopupView(
                voiceRecording: voiceRecording,
                isPresented: $showTranscriptionPopup
            )
        }
        .onDisappear {
            stopPlayback()
            resetPlayback()
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
            resetPlayback()
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = AudioPlayerDelegateHandler(onFinished: {
                stopPlayback()
            })
            audioPlayer?.play()
            audioPlayer?.volume = 1.0
            isPlaying = true
            startProgressTimer()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func resetPlayback() {
        currentTime = 0
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard let player = audioPlayer else {
                timer.invalidate()
                progressTimer = nil
                return
            }

            if player.isPlaying {
                currentTime = player.currentTime
            } else {
                currentTime = voiceRecording.duration
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
