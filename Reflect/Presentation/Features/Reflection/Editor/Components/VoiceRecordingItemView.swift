import SwiftUI

struct VoiceRecordingItemView: View {
    let recording: VoiceRecordingInput
    let onPlay: () -> Void
    let onRemove: () -> Void

    @State private var showPlayerPopup = false

    var body: some View {
        Button {
            showPlayerPopup = true
        } label: {
            HStack(spacing: Constants.Spacing.sm) {
                // Waveform preview
                waveformPreview

                // Duration Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Note")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)

                    Text(formatDuration(recording.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Play icon indicator
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundColor(.primaryDefault)
            }
            .padding(.vertical, Constants.Spacing.sm)
            .padding(.horizontal, Constants.Spacing.md)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(Constants.CornerRadius.medium)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPlayerPopup) {
            VoiceAudioView(mode: .play(recording), isPresented: $showPlayerPopup)
        }
    }

    private var waveformPreview: some View {
        ReflectWaveform(content: .preview(samples: recording.waveformSamples), style: .compact)
            .frame(height: 20)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VoiceRecordingItemView(
        recording: VoiceRecordingInput(
            audioData: Data(),
            transcription: "Sample transcription",
            language: "id-ID",
            duration: 45.5
        ),
        onPlay: {},
        onRemove: {}
    )
    .padding()
}
