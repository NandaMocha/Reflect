import SwiftUI
import SwiftData

struct StreakDetailView: View {
    @State private var streakViewModel: StreakViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var badgeViewModel: BadgeGridViewModel?

    @Environment(\.dismiss) var dismiss

    init(streakViewModel: StreakViewModel) {
        self._streakViewModel = State(initialValue: streakViewModel)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if let stats = streakViewModel.streakStats {
                        // Stats Section
                        StreakStatsSection(
                            currentStreak: stats.currentStreak,
                            longestStreak: stats.longestStreak,
                            totalReflections: stats.totalReflections
                        )
                    } else {
                        // Loading placeholder
                        StreakStatsSection(
                            currentStreak: 0,
                            longestStreak: 0,
                            totalReflections: 0
                        )
                        .redacted(reason: .placeholder)
                    }

                    // Badge Grid
                    if let badgeViewModel = badgeViewModel {
                        BadgeGridView(viewModel: badgeViewModel) { badge in
                            handleBadgeTap(badge)
                        }
                    } else {
                        ProgressView("Loading badges...")
                    }
                }
                .padding()
            }
            .navigationTitle("Streak & Badges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            setupBadgeViewModel()
        }
    }

    private func setupBadgeViewModel() {
        badgeViewModel = BadgeGridViewModel(modelContext: modelContext)
        Task {
            await badgeViewModel?.loadBadges()
        }
    }

    private func handleBadgeTap(_ badge: Badge) {
        // For now, just print - can be expanded to show badge details
        print("Tapped badge: \(badge.name)")
    }
}

// MARK: - Preview

#Preview {
    Text("Streak Detail Preview")
        .navigationTitle("Streak & Badges")
}

// MARK: - Test Data Helper

private func setupTestData(in context: ModelContext) {
    Task {
        // Create test badges from new system
    let badges = [
        // Streak Badges
        Badge(from: .threeDayStreak),
        Badge(from: .sevenDayStreak),
        Badge(from: .fourteenDayStreak),
        Badge(from: .thirtyDayStreak),

        // Reflection Milestones
        Badge(from: .fiveReflections),
        Badge(from: .tenReflections),
        Badge(from: .twentyFiveReflections),
        Badge(from: .fiftyReflections),
        Badge(from: .hundredReflections),

        // Media Milestones
        Badge(from: .tenMedia),
        Badge(from: .fiftyMedia),

        // Prompt Milestones
        Badge(from: .tenPrompts),
        Badge(from: .fiftyPrompts),

        // Special Achievements
        Badge(from: .monthlyChampion),
        Badge(from: .perfectionist)
    ]

    // Unlock some badges
    badges[0].unlock() // 3-Day Streak
    badges[4].unlock() // Curious Mind (5 reflections)

    for badge in badges {
        context.insert(badge)
    }

    try? context.save()
    }
}
