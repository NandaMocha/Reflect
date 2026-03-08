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
                // Header: Icon
                HStack {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(backgroundColor)
                            .frame(width: 56, height: 56)

                        Image(systemName: badge.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(iconColor)
                    }

                    Spacer()
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Name
                    Text(badge.name)
                        .font(.headline)
                        .foregroundStyle(badge.isUnlocked ? .primary : .secondary)

                    // Description
                    Text(badge.badgeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
        case .monthlyStreak:
            return .orange
        case .permanent:
            return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Unlocked streak badge
        BadgeCard(badge: {
            let badge = Badge(from: .threeDayStreak)
            badge.unlock()
            return badge
        }()) {
            print("Tapped unlocked badge")
        }

        // Locked streak badge
        BadgeCard(badge: Badge(from: .sevenDayStreak)) {
            print("Tapped locked badge")
        }

        // Unlocked achievement badge
        BadgeCard(badge: {
            let badge = Badge(from: .fiveReflections)
            badge.unlock()
            return badge
        }()) {
            print("Tapped new badge")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
