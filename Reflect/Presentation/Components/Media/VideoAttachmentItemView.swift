import SwiftUI

struct VideoAttachmentItemView: View {
    let thumbnail: UIImage
    let duration: TimeInterval
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.sm) {
            // Thumbnail with play button overlay
            ZStack(alignment: .center) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.large))

                // Play button overlay
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    )
            }

            // Duration and remove button
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text("Video")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .padding(Constants.Spacing.sm)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.large))
    }

    private var durationText: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VStack {
        VideoAttachmentItemView(
            thumbnail: UIImage(systemName: "video") ?? UIImage(),
            duration: 125,
            onRemove: {}
        )
    }
    .padding()
}
