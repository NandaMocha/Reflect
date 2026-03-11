import SwiftUI
import SwiftData

struct BadgeGridView: View {
    @State private var viewModel: BadgeGridViewModel
    @State private var selectedBadge: Badge?
    var onBadgeTap: ((Badge) -> Void)?

    init(viewModel: BadgeGridViewModel, onBadgeTap: ((Badge) -> Void)? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.onBadgeTap = onBadgeTap
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    ProgressView("Loading achievements...")
                } else if viewModel.badges.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .padding()
        }
        .task {
            await viewModel.loadBadges()
        }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailView(badge: badge)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 24) {
            // Achievement Count Header
            achievementCountHeader

            // Latest Achieved (single landscape card)
            if let latestAchievement = viewModel.latestAchievement {
                latestAchievedSection(latestAchievement)
            }

            // All Achievements (2-column grid)
            allAchievementsGrid
        }
    }

    // MARK: - Achievement Count Header

    private var achievementCountHeader: some View {
        HStack {
            Text("\(viewModel.totalUnlocked)")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Achievements")
                    .font(.title2.bold())

                Text("of \(viewModel.totalBadges) unlocked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Latest Achieved Section

    private func latestAchievedSection(_ achievement: Badge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)

                Text("Latest Achieved")
                    .font(.headline)
            }

            LandscapeBadgeCard(badge: achievement) {
                selectedBadge = achievement
            }
        }
    }

    // MARK: - All Achievements Grid

    private var allAchievementsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Achievements")
                .font(.headline)

            if viewModel.badges.isEmpty {
                emptyAchievementBadgesState
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(sortedAchievements) { badge in
                        AchievementCard(badge: badge) {
                            selectedBadge = badge
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sorting

    private var sortedAchievements: [Badge] {
        let badges = viewModel.badges

        // Separate into unlocked and locked
        let unlocked = badges.filter { $0.isUnlocked }
        let locked = badges.filter { !$0.isUnlocked }

        // Sort unlocked by unlocked date (most recent first)
        let sortedUnlocked = unlocked.sorted { badge1, badge2 in
            (badge1.unlockedAt ?? .distantPast) > (badge2.unlockedAt ?? .distantPast)
        }

        // Sort locked by difficulty (easiest first)
        let sortedLocked = locked.sorted { badge1, badge2 in
            badgeDifficultyOrder(badge1) < badgeDifficultyOrder(badge2)
        }

        // Return: all unlocked first (by recency), then locked (by difficulty)
        return sortedUnlocked + sortedLocked
    }

    // Badge difficulty order: easiest (1) to hardest (10)
    private func badgeDifficultyOrder(_ badge: Badge) -> Int {
        let difficultyMap: [String: Int] = [
            // Special achievements
            "monthly-champion": 6,
            "perfectionist": 7,
            "quarterly-champion": 8,
            "half-year-hero": 9,
            // Reflection milestones (easiest first)
            "5-reflections": 1,
            "10-reflections": 2,
            "25-reflections": 3,
            "50-reflections": 4,
            "100-reflections": 5,
            "250-reflections": 6,
            "500-reflections": 7,
            "1000-reflections": 8,
            // Media milestones
            "10-media": 2,
            "50-media": 5,
            "100-media": 7,
            // Prompt milestones
            "10-prompts": 2,
            "50-prompts": 5,
            "100-prompts": 7
        ]
        return difficultyMap[badge.id] ?? 999
    }

    // MARK: - Empty States

    private var emptyAchievementBadgesState: some View {
        HStack {
            VStack(spacing: 8) {
                Image(systemName: "medal")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("No achievements yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Keep reflecting to earn milestones!")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "medal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Achievements Yet")
                .font(.headline)

            Text("Start reflecting to earn your first achievement!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Achievement Card (Square)

struct AchievementCard: View {
    let badge: Badge
    let onTap: () -> Void

    private var requiredCount: Int {
        // Get required count from BadgeID
        if let badgeID = BadgeID(rawValue: badge.id) {
            return badgeID.requiredCount
        }
        return 1 // Default fallback
    }

    private var currentProgress: Int {
        badge.unlockedCount
    }

    var body: some View {
        VStack(spacing: 8) {
            // Achievement Icon
            Image(systemName: badge.icon)
                .font(.system(size: 44))
                .foregroundStyle(badge.isUnlocked ? .blue : .secondary)
                .frame(width: 80, height: 80)

            // Achievement Title
            Text(badge.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Short Description
            Text(badge.badgeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Progress Indicator
            AchievementProgressBar(
                current: currentProgress,
                target: requiredCount
            )
            .frame(height: 8)

            // Current/Target Text
            Text("\(currentProgress)/\(requiredCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Achievement Progress Bar

struct AchievementProgressBar: View {
    let current: Int
    let target: Int

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))

                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
    }

    private var progressColor: Color {
        if progress >= 1.0 {
            return .green
        } else if progress >= 0.5 {
            return .blue
        } else {
            return .orange
        }
    }
}

// MARK: - Preview

#Preview {
    Text("Badge Grid Preview")
}
