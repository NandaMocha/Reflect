import SwiftUI

struct VoiceRecordingItemView: View {
    let recording: VoiceRecordingInput
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            // Play Button
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.primaryDefault)
                    .clipShape(Circle())
            }

            // Duration Info
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice Note")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)

                Text(formatDuration(recording.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Remove Button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Constants.Spacing.xs)
        .padding(.horizontal, Constants.Spacing.sm)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(Constants.CornerRadius.medium)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
