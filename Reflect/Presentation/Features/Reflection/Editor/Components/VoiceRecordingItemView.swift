import SwiftUI

struct VoiceRecordingItemView: View {
    let recording: VoiceRecordingInput
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundColor(.primaryDefault)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Voice Note")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)

                Text(formatDuration(recording.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Constants.Spacing.xs)
        .padding(.horizontal, Constants.Spacing.sm)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
