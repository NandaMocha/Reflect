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
                    ProgressView("Loading badges...")
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
            // Progress Header
            progressHeader

            // Newly Unlocked Section (if any) - Landscape cards
            if viewModel.hasNewUnlocks {
                newlyUnlockedSection
            }

            // All Badges (combined list)
            allBadgesSection
        }
    }

    // MARK: - Sections

    private var progressHeader: some View {
        VStack(spacing: 8) {
            Text("Your Badges")
                .font(.title2.bold())

            // Progress bar
            VStack(spacing: 4) {
                HStack {
                    Text("\(viewModel.totalUnlocked) of \(viewModel.totalBadges)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(.blue)
                            .frame(width: geometry.size.width * viewModel.progress, height: 8)
                            .animation(.easeInOut, value: viewModel.progress)
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private var newlyUnlockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)

                Text("Recently Unlocked")
                    .font(.headline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.newlyUnlockedBadges) { badge in
                        LandscapeBadgeCard(badge: badge) {
                            selectedBadge = badge
                        }
                        .frame(width: .infinity)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var allBadgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Badges")
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(sortedBadges) { badge in
                    BadgeCard(badge: badge) {
                        selectedBadge = badge
                    }
                }
            }
        }
    }

    // All badges sorted: unlocked first (by difficulty), then locked (by difficulty)
    private var sortedBadges: [Badge] {
        // Separate into unlocked and locked
        let unlocked = viewModel.badges.filter { $0.isUnlocked }
        let locked = viewModel.badges.filter { !$0.isUnlocked }

        // Sort unlocked by difficulty (easiest first)
        let sortedUnlocked = unlocked.sorted { badge1, badge2 in
            badgeDifficultyOrder(badge1) < badgeDifficultyOrder(badge2)
        }

        // Sort locked by difficulty (easiest first)
        let sortedLocked = locked.sorted { badge1, badge2 in
            badgeDifficultyOrder(badge1) < badgeDifficultyOrder(badge2)
        }

        // Return: all unlocked first, then locked
        return sortedUnlocked + sortedLocked
    }

    // Badge difficulty order: easiest (1) to hardest (10)
    private func badgeDifficultyOrder(_ badge: Badge) -> Int {
        let difficultyMap: [String: Int] = [
            "first-reflection": 1,        // Easiest
            "3day-streak": 2,
            "7day-streak": 3,
            "14day-streak": 4,
            "30day-streak": 5,
            "first-day-month": 6,
            "half-month": 7,
            "full-month": 8,
            "6month-consistency": 9,
            "12month-consistency": 10     // Hardest
        ]
        return difficultyMap[badge.id] ?? 999
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "medal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Badges Yet")
                .font(.headline)

            Text("Start reflecting to earn your first badge!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Preview

#Preview {
    Text("Badge Grid Preview")
}
