import SwiftUI

struct StreakStatsSection: View {
    let currentStreak: Int
    let longestStreak: Int
    let totalReflections: Int

    var nextMilestone: Int {
        // Find next streak milestone (3, 7, 14, 30)
        let milestones = [3, 7, 14, 30]
        for milestone in milestones {
            if currentStreak < milestone {
                return milestone
            }
        }
        return currentStreak + 30 // Next 30-day cycle
    }

    var progressToNext: Double {
        if currentStreak >= 30 {
            return 1.0
        }
        let previousMilestone = [0, 3, 7, 14, 30].first { $0 >= currentStreak } ?? 0
        let next = [3, 7, 14, 30].first { $0 > currentStreak } ?? 30
        return Double(currentStreak - previousMilestone) / Double(next - previousMilestone)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Current Streak
            VStack(spacing: 8) {
                Text("Current Streak")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(currentStreak)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(streakColor)

                    Text("Day\(currentStreak == 1 ? "" : "s")")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }
            }

            // Progress to next milestone
            if currentStreak < 30 {
                VStack(spacing: 6) {
                    HStack {
                        Text("Next: \(nextMilestone)-Day Streak")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(nextMilestone - currentStreak) to go")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(streakColor)
                                .frame(width: geometry.size.width * progressToNext, height: 6)
                                .animation(.easeInOut, value: progressToNext)
                        }
                    }
                    .frame(height: 6)
                }
            }

            Divider()

            // Stats Row
            HStack(spacing: 20) {
                StatItem(
                    icon: "flame.fill",
                    title: "Longest",
                    value: "\(longestStreak)",
                    subtitle: "day\(longestStreak == 1 ? "" : "s")"
                )

                Spacer()

                StatItem(
                    icon: "doc.text.fill",
                    title: "Total",
                    value: "\(totalReflections)",
                    subtitle: "reflection\(totalReflections == 1 ? "" : "s")"
                )
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var streakColor: Color {
        switch currentStreak {
        case 0:
            return .gray
        case 1...2:
            return .orange
        case 3...6:
            return .orange
        case 7...13:
            return .red
        case 14...29:
            return .purple
        default:
            return .blue
        }
    }
}

// MARK: - Stat Item Component

struct StatItem: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.bold())

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        StreakStatsSection(
            currentStreak: 5,
            longestStreak: 14,
            totalReflections: 42
        )

        StreakStatsSection(
            currentStreak: 0,
            longestStreak: 0,
            totalReflections: 0
        )

        StreakStatsSection(
            currentStreak: 30,
            longestStreak: 30,
            totalReflections: 100
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
