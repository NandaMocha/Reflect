import SwiftUI

/// Pure visual card. Callers wrap in `NavigationLink(value:)` or `Button` for tap handling.
/// Does not wrap its content in a Button itself — a nested Button would eat taps from any
/// outer NavigationLink and break navigation (see ReflectionListView).
struct ReflectionCard: View {
    let reflection: Reflection

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                Text(reflection.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(reflection.contentPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                HStack(spacing: Constants.Spacing.xs) {
                    // Media indicators
                    if reflection.hasImages || reflection.hasVoiceRecordings || reflection.hasVideos {
                        HStack(spacing: Constants.Spacing.xxs) {
                            if reflection.hasImages {
                                Image(systemName: "photo")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if reflection.hasVoiceRecordings {
                                Image(systemName: "mic")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if reflection.hasVideos {
                                Image(systemName: "video")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Date
                    Text(reflection.createdAt.shortFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: Constants.Spacing.xs) {
                ///NOTE: Below is the thumbnail image which can be refactor as universal component
                if let thumbnail = reflection.firstThumbnailImage {
                    ZStack {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))

                        // Play icon overlay for videos (when video is the primary media)
                        if reflection.hasVideos && !reflection.hasImages {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                }

                // Show count badge if multiple media items
                let mediaCount = reflection.hasImages ? reflection.images.count : reflection.videos.count
                if mediaCount > 1 {
                    Text("+ \(mediaCount - 1)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 50, alignment: .center)
                }
            }
        }
        .glassCard()
    }
}

// MARK: - Compact Variant

struct ReflectionCardCompact: View {
    let reflection: Reflection

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text(reflection.title)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(reflection.contentPreview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                Text(reflection.createdAt.shortFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding(Constants.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

#Preview {
    let reflection = Reflection(
        title: "Today's Learning Reflection",
        plainTextContent: "I learned a lot about SwiftUI today. The declarative syntax is really intuitive and makes building UIs much faster."
    )

    VStack(spacing: 16) {
        ReflectionCard(reflection: reflection)
        ReflectionCardCompact(reflection: reflection)
    }
    .padding()
}
