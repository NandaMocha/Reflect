import SwiftUI

struct BadgeDetailView: View {
    let badge: Badge
    @Environment(\.dismiss) var dismiss

    private var requiredCount: Int {
        if let badgeID = BadgeID(rawValue: badge.id) {
            return badgeID.requiredCount
        }
        return 1
    }

    /// See AchievementCard.currentProgress — cap at threshold for display.
    private var currentProgress: Int {
        min(badge.unlockedCount, requiredCount)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Badge Icon
                    badgeIcon

                    // Badge Info
                    VStack(spacing: 16) {
                        Text(badge.name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text(badge.badgeDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Progress Section (if not unlocked or has progress)
                    if !badge.isUnlocked || currentProgress > requiredCount {
                        progressSection
                    }

                    // How to Achieve Section
                    HowToAchieveCard(badge: badge)

                    // Status Info
                    VStack(spacing: 12) {
                        statusCard

                        if badge.isUnlocked, let unlockedAt = badge.unlockedAt {
                            unlockInfo(unlockedAt)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }
            .navigationTitle("Achievement Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var badgeIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 120, height: 120)

            Image(systemName: badge.icon)
                .font(.system(size: 50))
                .foregroundStyle(iconColor)
        }
        .shadow(color: iconColor.opacity(0.3), radius: 10)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)

                Text("Progress")
                    .font(.headline)
            }

            // Progress Bar
            AchievementProgressBar(
                current: currentProgress,
                target: requiredCount
            )
            .frame(height: 12)

            // Progress Text
            HStack {
                Text("\(currentProgress) of \(requiredCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if badge.isUnlocked {
                    Text("✓ Completed")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                } else {
                    let remaining = requiredCount - currentProgress
                    Text("\(remaining) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusCard: some View {
        HStack {
            Image(systemName: badge.isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                .font(.title2)
                .foregroundStyle(badge.isUnlocked ? .green : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(badge.isUnlocked ? "Unlocked" : "Locked")
                    .font(.headline)
                    .foregroundStyle(badge.isUnlocked ? .green : .gray)

                Text(badge.isUnlocked ? "You've earned this achievement!" : "Keep reflecting to unlock this achievement")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func unlockInfo(_ unlockedAt: Date) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)

                Text("Earned \(unlockedAt, format: .dateTime.month().day().year().hour().minute())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if badge.unlockedCount > 1 {
                HStack {
                    Image(systemName: "repeat")
                        .foregroundStyle(.secondary)

                    Text("Earned after: \(badge.unlockedCount) reflections")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var iconBackgroundColor: Color {
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

    private var accentColor: Color {
        switch badge.type {
        case .permanent:
            return .blue
        }
    }
}

#Preview {
    BadgeDetailView(badge: {
        let badge = Badge(from: .fiveReflections)
        badge.isUnlocked = true
        badge.unlockedCount = 5
        badge.unlockedAt = Date()
        return badge
    }())
}
