import SwiftUI

/// Pure visual card. Callers wrap in `NavigationLink(value:)` or `Button` for tap handling.
/// Does not wrap its content in a Button itself — a nested Button would eat taps from any
/// outer NavigationLink and break navigation (see ReflectionListView).
struct ReflectionCard: View {
    let reflection: Reflection

    var body: some View {
        let mediaCount = reflection.hasImages ? reflection.images.count : reflection.videos.count
        EntryCard(
            title: reflection.title,
            bodyText: reflection.contentPreview,
            dateText: reflection.createdAt.shortFormatted,
            hasImages: reflection.hasImages,
            hasVoiceRecordings: reflection.hasVoiceRecordings,
            hasVideos: reflection.hasVideos,
            thumbnail: reflection.firstThumbnailImage,
            extraMediaCount: mediaCount > 1 ? mediaCount - 1 : 0
        )
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
