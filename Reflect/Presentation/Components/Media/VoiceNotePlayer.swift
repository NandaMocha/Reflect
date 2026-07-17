import SwiftUI
import AVFoundation

struct VoiceNotePlayer: View {
    let voiceRecording: VoiceRecording

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var progressTimer: Timer?
    @State private var showTranscriptionPopup = false
    @State private var backfilledSamples: [Float] = []

    /// Stored samples if present, otherwise the ones analyzed on the fly for legacy recordings.
    private var displaySamples: [Float] {
        voiceRecording.waveformSamples.isEmpty ? backfilledSamples : voiceRecording.waveformSamples
    }

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

            // Waveform Preview & Progress
            VStack(spacing: 2) {
                // Waveform visualization with progress
                ReflectWaveform(content: .playback(samples: displaySamples, progress: Double(progress)), style: .compact)
                .frame(height: 20)
                .animation(.linear(duration: 0.1), value: progress)

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
        .task {
            // Legacy recordings have no stored samples — analyze the audio once so the waveform
            // shows real amplitude instead of a flat baseline.
            if voiceRecording.waveformSamples.isEmpty, let data = voiceRecording.audioData {
                backfilledSamples = await WaveformSampleLoader.samples(from: data)
            }
        }
    }

    // MARK: - Computed Properties

    private var progress: CGFloat {
        guard voiceRecording.duration > 0 else { return 0 }
        return CGFloat(currentTime / voiceRecording.duration)
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
            // If no player exists or playback finished, create new player and reset to start
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.delegate = AudioPlayerDelegateHandler(onFinished: {
                    stopPlayback()
                })
                audioPlayer?.currentTime = currentTime // Resume from where paused
            }

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
        language: "id-ID",
        duration: 45
    )

    VoiceNotePlayer(voiceRecording: recording)
        .padding()
}
