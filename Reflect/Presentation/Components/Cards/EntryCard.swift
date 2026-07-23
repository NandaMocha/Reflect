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
    /// Duration string for a voice-only entry (e.g. "0:42"). Shown under the trailing
    /// voice tile when there's no image/video thumbnail to display.
    var voiceDurationText: String? = nil

    /// Insight "Followed up" badge.
    var showFollowedUp: Bool = false

    private var hasMedia: Bool { hasImages || hasVoiceRecordings || hasVideos }

    /// A reflection whose only media is voice (no image/video thumbnail). These get a
    /// waveform tile in the trailing column instead of the empty space a plain text or
    /// text-with-no-thumbnail entry would leave there.
    private var isVoiceOnly: Bool { hasVoiceRecordings && !hasImages && !hasVideos }

    /// Show the inline media-icon row only when there's actually an icon to show. The mic
    /// is redundant for voice-only entries (the trailing waveform tile already signals it).
    private var showsMediaIcons: Bool {
        hasImages || hasVideos || (hasVoiceRecordings && !isVoiceOnly)
    }

    /// Whether there's any body/preview text to show. A reflection can have an empty body
    /// (e.g. an image- or voice-only entry), in which case the text line is skipped so the
    /// date stays tucked right under the title instead of sitting past an empty gap.
    private var hasBodyText: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                if let tag {
                    tagPill(tag)
                }

                if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // The description sits under the title only when there is one, so a
                    // reflection with no body (image- or voice-only) doesn't leave an
                    // empty line pushing the date away from the title.
                    if hasBodyText {
                        Text(bodyText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                } else if hasBodyText {
                    // No title (insights, or a media-only reflection): the text itself is
                    // the primary line.
                    Text(bodyText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                // Push the date to the bottom (aligning it with the thumbnail) only when
                // there's body text above it. Without a description the date stays close
                // under the title rather than floating far below it.
                if hasBodyText {
                    Spacer(minLength: 8)
                }

                HStack(spacing: Constants.Spacing.xs) {
                    if showsMediaIcons {
                        HStack(spacing: Constants.Spacing.xxs) {
                            if hasImages {
                                Image(systemName: "photo")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if hasVoiceRecordings && !isVoiceOnly {
                                Image(systemName: "mic")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if hasVideos {
                                Image(systemName: "video")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text(dateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

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
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                } else if isVoiceOnly {
                    voiceTile
                }

                if extraMediaCount > 0 {
                    Text("+ \(extraMediaCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 50, alignment: .center)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Subviews

    /// Trailing tile for a voice-only entry: a waveform glyph sized like the image
    /// thumbnail, with the recording's duration beneath it.
    private var voiceTile: some View {
        VStack(spacing: Constants.Spacing.xxs) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primaryDefault)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                        .fill(Color.primaryDefault.opacity(0.12))
                )

            if let voiceDurationText {
                Text(voiceDurationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

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
        let color = Color(hex: "628141")
        // Explicit HStack (not Label) so the badge hugs its content and keeps the icon
        // and text at a consistent size — matching the type tag pill.
        return HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
            Text("Followed up")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Constants.Spacing.xs)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(color.opacity(0.12))
        )
    }
}
