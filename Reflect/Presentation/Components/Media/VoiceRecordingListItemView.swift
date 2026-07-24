import SwiftUI

/// A list item view for voice recordings that opens a full-screen player popup
/// Used in ReflectionDetailView for consistent UI with ReflectionEditorView
struct VoiceRecordingListItemView: View {
    let voiceRecording: VoiceRecording

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
                        .foregroundStyle(.primary)

                    Text(formatDuration(voiceRecording.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Play icon indicator
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.primaryDefault)
            }
            .padding(.vertical, Constants.Spacing.sm)
            .padding(.horizontal, Constants.Spacing.md)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: Constants.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPlayerPopup) {
            VoiceAudioView(mode: .play(voiceRecording.toInput()), isPresented: $showPlayerPopup)
        }
    }

    private var waveformPreview: some View {
        ReflectWaveform(content: .preview(samples: voiceRecording.waveformSamples), style: .compact)
            .frame(height: 20)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    let recording = VoiceRecording(
        audioData: nil,
        transcription: "Sample transcription",
        language: "id-ID",
        duration: 45.5
    )

    VoiceRecordingListItemView(voiceRecording: recording)
        .padding()
}
