import SwiftUI

struct BadgeCard: View {
    let badge: Badge
    var onTap: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            onTap?()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Icon + Status
                HStack {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(backgroundColor)
                            .frame(width: 56, height: 56)

                        Image(systemName: badge.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(iconColor)
                    }

                    Spacer()

                    // Status badge
                    if badge.isUnlocked {
                        statusBadge
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Name with new indicator
                    HStack(spacing: 6) {
                        Text(badge.name)
                            .font(.headline)
                            .foregroundStyle(badge.isUnlocked ? .primary : .secondary)

                        if badge.isNew {
                            newIndicator
                        }
                    }

                    // Description
                    Text(badge.badgeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Footer (only show if unlocked)
                if badge.isUnlocked, let unlockedAt = badge.unlockedAt {
                    footer(unlockedAt)
                }
            }
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(cardBorder)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    // MARK: - Helper Views

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.bold())

            Text("Earned")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var newIndicator: some View {
        Text("NEW")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange)
            .clipShape(Capsule())
    }

    private func footer(_ unlockedAt: Date) -> some View {
        HStack {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Earned \(unlockedAt, style: .relative)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if badge.unlockedCount > 1 {
                Text("×\(badge.unlockedCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Style Properties

    private var backgroundColor: Color {
        if badge.isUnlocked {
            return iconColor.opacity(0.15)
        } else {
            return Color.gray.opacity(0.1)
        }
    }

    private var iconColor: Color {
        if badge.isUnlocked {
            return accentColor
        } else {
            return Color.gray
        }
    }

    private var cardBackground: Color {
        if badge.isUnlocked {
            return Color(.systemBackground)
        } else {
            return Color(.secondarySystemBackground)
        }
    }

    private var cardBorder: some View {
        Group {
            if badge.isUnlocked {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(accentColor.opacity(0.3), lineWidth: 2)
            } else {
                EmptyView()
            }
        }
    }

    private var accentColor: Color {
        // Return different colors based on badge type
        switch badge.type {
        case .repeatedStreak:
            return .orange
        case .permanent:
            return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Unlocked badge
        BadgeCard(badge: {
            let badge = Badge(from: .threeDay)
            badge.unlock()
            return badge
        }()) {
            print("Tapped unlocked badge")
        }

        // Locked badge
        BadgeCard(badge: Badge(from: .sevenDay)) {
            print("Tapped locked badge")
        }

        // New badge
        BadgeCard(badge: {
            let badge = Badge(from: .firstReflection)
            badge.unlock()
            return badge
        }()) {
            print("Tapped new badge")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
