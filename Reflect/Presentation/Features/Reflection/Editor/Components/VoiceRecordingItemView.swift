import SwiftUI

struct VoiceRecordingItemView: View {
    let recording: VoiceRecordingInput
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.primaryDefault)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(formatDuration(recording.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Waveform visualization placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primaryDefault.opacity(0.3))
                    .frame(height: 40)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
