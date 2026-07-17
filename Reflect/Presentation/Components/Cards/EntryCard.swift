import SwiftUI

/// A small leading pill (icon + label), e.g. an Insight's type tag. Absent for reflections.
struct EntryCardTag {
    let label: String
    let icon: String
    /// Hex string (with or without `#`) resolved via `Color(hex:)`.
    let colorHex: String
}

/// Shared visual row card used by BOTH the Reflection and Insight lists, so the two
/// features render as one consistent list item.
///
/// Pure visual — callers wrap it in a `Button`/`NavigationLink` for tap handling.
/// Everything that only applies to one feature is optional and hidden when unset:
/// - `tag` / `showFollowedUp` are for Insights (reflections pass neither).
/// - `title`, media indicators, and `thumbnail` are for Reflections (insights pass none).
struct EntryCard: View {
    /// Insight type tag. `nil` for reflections (hidden).
    var tag: EntryCardTag? = nil
    /// Bold headline title (reflections). `nil` for insights — then `bodyText` becomes the
    /// primary line.
    var title: String? = nil
    /// Main content / preview text.
    let bodyText: String
    /// Preformatted date string (each feature chooses its own format).
    let dateText: String

    // Reflection media (all default off → hidden for insights)
    var hasImages: Bool = false
    var hasVoiceRecordings: Bool = false
    var hasVideos: Bool = false
    var thumbnail: UIImage? = nil
    var extraMediaCount: Int = 0

    /// Insight "Followed up" badge.
    var showFollowedUp: Bool = false

    private var hasMedia: Bool { hasImages || hasVoiceRecordings || hasVideos }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                if let tag {
                    tagPill(tag)
                }

                if let title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(bodyText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    // No title (insights): the text itself is the primary line.
                    Text(bodyText)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                HStack(spacing: Constants.Spacing.xs) {
                    if hasMedia {
                        HStack(spacing: Constants.Spacing.xxs) {
                            if hasImages {
                                Image(systemName: "photo")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if hasVoiceRecordings {
                                Image(systemName: "mic")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if hasVideos {
                                Image(systemName: "video")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Text(dateText)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if showFollowedUp {
                        followedUpBadge
                    }
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: Constants.Spacing.xs) {
                if let thumbnail {
                    ZStack {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))

                        // Play icon overlay for videos (when video is the primary media)
                        if hasVideos && !hasImages {
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

                if extraMediaCount > 0 {
                    Text("+ \(extraMediaCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 50, alignment: .center)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Subviews

    private func tagPill(_ tag: EntryCardTag) -> some View {
        let color = Color(hex: tag.colorHex)
        // Explicit HStack (not Label) so the pill hugs the label's width instead of
        // stretching, and never drops the title.
        return HStack(spacing: 3) {
            Image(systemName: tag.icon)
                .font(.caption2)
            Text(tag.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Constants.Spacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(color.opacity(0.18))
        )
    }

    private var followedUpBadge: some View {
        Label("Followed up", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(hex: "628141"))
            .padding(.horizontal, Constants.Spacing.xs)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color(hex: "628141").opacity(0.12))
            )
    }
}
