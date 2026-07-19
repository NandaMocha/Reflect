import SwiftUI

/// A single space in the list: emoji/glyph, name, optional detail, owner badge (vs
/// joined), and participant count.
struct SpaceRowView: View {
    let space: Space

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if let detail = space.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: Constants.Spacing.xs) {
                    if space.isOwner {
                        Text("Owner")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.15))
                            )
                            .foregroundStyle(Color.accentColor)
                    }

                    Label("\(space.participantCount)", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(Color.secondary.opacity(0.12))

            if let emoji = space.emoji, !emoji.isEmpty {
                Text(emoji).font(.title2)
            } else {
                Image(systemName: "person.3.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
    }
}
