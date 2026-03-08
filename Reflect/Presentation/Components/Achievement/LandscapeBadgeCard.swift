import SwiftUI

struct LandscapeBadgeCard: View {
    let badge: Badge
    var onTap: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            onTap?()
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 64, height: 64)

                    Image(systemName: badge.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(iconColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // Name
                    Text(badge.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // Description
                    Text(badge.badgeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
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
        return iconColor.opacity(0.15)
    }

    private var iconColor: Color {
        return accentColor
    }

    private var cardBackground: Color {
        return Color(.systemBackground)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(accentColor.opacity(0.3), lineWidth: 2)
    }

    private var accentColor: Color {
        switch badge.type {
        case .monthlyStreak:
            return .orange
        case .permanent:
            return .blue
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        LandscapeBadgeCard(badge: {
            let badge = Badge(from: .threeDayStreak)
            badge.unlock()
            return badge
        }()) {
            print("Tapped landscape badge")
        }

        LandscapeBadgeCard(badge: {
            let badge = Badge(from: .fiveReflections)
            badge.unlock()
            return badge
        }()) {
            print("Tapped landscape badge")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
