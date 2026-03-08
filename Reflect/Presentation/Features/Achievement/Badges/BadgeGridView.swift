import SwiftUI
import SwiftData

struct BadgeGridView: View {
    @State private var viewModel: BadgeGridViewModel
    @State private var selectedBadge: Badge?
    @State private var calendarViewModel: CalendarHeatmapViewModel?
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
            // Initialize calendar view model with same month
            if calendarViewModel == nil {
                let vm = CalendarHeatmapViewModel(modelContext: viewModel.modelContext)
                vm.selectedMonth = viewModel.selectedMonth
                calendarViewModel = vm
            }
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

            // Month Selector for Streak Badges
            monthSelectorSection

            // Streak Badges for Selected Month
            streakBadgesSection

            // Calendar Heatmap Section
            if let calendarViewModel = calendarViewModel {
                calendarHeatmapSection(calendarViewModel)
            }

            // Achievement Badges (Permanent) - Section divider
            achievementBadgesSection
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

    // MARK: - Month Selector Section

    private var monthSelectorSection: some View {
        MonthSelectorView(
            currentMonth: viewModel.selectedMonth,
            hasPrevious: viewModel.hasPreviousMonth,
            hasNext: viewModel.hasNextMonth,
            onPrevious: {
                withAnimation(.easeInOut) {
                    viewModel.selectPreviousMonth()
                    // Sync calendar month
                    if var calendarVM = calendarViewModel {
                        calendarVM.selectedMonth = viewModel.selectedMonth
                    }
                }
            },
            onNext: {
                withAnimation(.easeInOut) {
                    viewModel.selectNextMonth()
                    // Sync calendar month
                    if var calendarVM = calendarViewModel {
                        calendarVM.selectedMonth = viewModel.selectedMonth
                    }
                }
            }
        )
    }

    // MARK: - Streak Badges Section

    private var streakBadgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)

                Text("Streak Badges")
                    .font(.headline)

                Text("(\(viewModel.selectedMonthYearString))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let streakBadges = viewModel.streakBadgesForSelectedMonth
            if streakBadges.isEmpty {
                emptyStreakBadgesState
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(streakBadges) { badge in
                        BadgeCard(badge: badge) {
                            selectedBadge = badge
                        }
                    }
                }
            }
        }
    }

    private var emptyStreakBadgesState: some View {
        HStack {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("No streak badges for this month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Start reflecting to build your streak!")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Calendar Heatmap Section

    private func calendarHeatmapSection(_ calendarViewModel: CalendarHeatmapViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.green)

                Text("Reflection Calendar")
                    .font(.headline)

                Text("(\(calendarViewModel.selectedMonthYearString))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            MonthlyCalendarHeatmap(viewModel: calendarViewModel) { newMonth in
                // Sync badge selector month when calendar changes
                withAnimation(.easeInOut) {
                    viewModel.selectedMonth = newMonth
                }
            }
        }
    }

    // MARK: - Achievement Badges Section

    private var achievementBadgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.blue)

                Text("Achievement Badges")
                    .font(.headline)

                Text("(Lifetime)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let permanentBadges = viewModel.permanentBadges
            if permanentBadges.isEmpty {
                emptyAchievementBadgesState
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(sortedPermanentBadges) { badge in
                        BadgeCard(badge: badge) {
                            selectedBadge = badge
                        }
                    }
                }
            }
        }
    }

    private var emptyAchievementBadgesState: some View {
        HStack {
            VStack(spacing: 8) {
                Image(systemName: "medal")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("No achievement badges yet")
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

    // Permanent badges sorted: unlocked first (by difficulty), then locked (by difficulty)
    private var sortedPermanentBadges: [Badge] {
        let badges = viewModel.permanentBadges

        // Separate into unlocked and locked
        let unlocked = badges.filter { $0.isUnlocked }
        let locked = badges.filter { !$0.isUnlocked }

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
            // Streak badges
            "3day-streak": 2,
            "7day-streak": 3,
            "14day-streak": 4,
            "30day-streak": 5,
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
