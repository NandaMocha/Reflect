import SwiftUI

/// A single space in the list: emoji/glyph avatar, name, optional detail, an owner/joined
/// badge, and the participant count.
struct SpaceRowView: View {
    let space: Space

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let detail = space.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: Constants.Spacing.xs) {
                    roleBadge
                    participantCount
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

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

    private var roleBadge: some View {
        Text(space.isOwner ? "Owner" : "Joined")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(badgeColor.opacity(0.15)))
            .foregroundStyle(badgeColor)
    }

    // Explicit icon + number (not a `Label`, which can split its icon and title apart
    // inside a List/NavigationLink row).
    private var participantCount: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.2.fill")
            Text("\(space.participantCount)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var badgeColor: Color {
        space.isOwner ? Color.accentColor : Color.secondary
    }
}

#Preview {
    List {
        SpaceRowView(space: Space(
            id: "1", name: "C3 Menthol", detail: "Reflections on the menthol batch",
            emoji: nil, isOwner: true,
            zoneID: SpaceZoneRef(zoneName: "z", ownerName: "o", lane: .privateDB),
            createdAt: Date(), participantCount: 1
        ))
        SpaceRowView(space: Space(
            id: "2", name: "Study Group", detail: nil, emoji: "📚", isOwner: false,
            zoneID: SpaceZoneRef(zoneName: "z2", ownerName: "o2", lane: .sharedDB),
            createdAt: Date(), participantCount: 4
        ))
    }
    .listStyle(.plain)
}
