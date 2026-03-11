import Foundation
import SwiftData
import Observation

@Observable
final class BadgeGridViewModel {
    private let badgeRepository: BadgeRepositoryProtocol
    private let calendar = Calendar.current
    let modelContext: ModelContext

    var badges: [Badge] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // Month Navigation State
    var selectedMonth: Date = Date()

    // Filtered badges
    var unlockedBadges: [Badge] {
        badges.filter { $0.isUnlocked }
        .sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
    }

    var lockedBadges: [Badge] {
        badges.filter { !$0.isUnlocked }
        .sorted { $0.name < $1.name }
    }

    var newlyUnlockedBadges: [Badge] {
        badges.filter { $0.isNew }
    }

    var hasNewUnlocks: Bool {
        !newlyUnlockedBadges.isEmpty
    }

    // MARK: - Badge Categories

    /// All permanent achievement badges (all badges are now permanent after removing streaks)
    var permanentBadges: [Badge] {
        badges  // All badges are permanent now
    }

    // MARK: - Month Navigation Helpers

    var hasPreviousMonth: Bool {
        guard let earliestMonth = earliestBadgeMonth else { return false }
        let currentComponents = calendar.dateComponents([.month, .year], from: selectedMonth)
        let earliestComponents = calendar.dateComponents([.month, .year], from: earliestMonth)

        // Can go back if current month is after earliest month
        if let currentYear = currentComponents.year,
           let earliestYear = earliestComponents.year,
           let currentMonth = currentComponents.month,
           let earliestMonth = earliestComponents.month {
            if currentYear > earliestYear {
                return true
            } else if currentYear == earliestYear && currentMonth > earliestMonth {
                return true
            }
        }
        return false
    }

    var hasNextMonth: Bool {
        // Only allow going forward if current month is before current actual month
        let currentComponents = calendar.dateComponents([.month, .year], from: selectedMonth)
        let todayComponents = calendar.dateComponents([.month, .year], from: Date())

        guard let currentYear = currentComponents.year,
              let currentMonth = currentComponents.month,
              let todayYear = todayComponents.year,
              let todayMonth = todayComponents.month else {
            return false
        }

        // Can only go forward if selected month is strictly before current month
        return currentYear < todayYear || (currentYear == todayYear && currentMonth < todayMonth)
    }

    private var earliestBadgeMonth: Date? {
        // No more monthly streak badges - return nil
        return nil
    }

    // Stats
    var totalUnlocked: Int {
        badges.filter { $0.isUnlocked }.count
    }

    var totalBadges: Int {
        badges.count
    }

    var progress: Double {
        guard totalBadges > 0 else { return 0 }
        return Double(totalUnlocked) / Double(totalBadges)
    }

    var selectedMonthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.badgeRepository = BadgeRepository(modelContext: modelContext)
    }

    init(badgeRepository: BadgeRepositoryProtocol) {
        // For testing purposes - create a temporary context
        // This should not be used in production
        fatalError("Use init(modelContext:) instead")
    }

    // MARK: - Actions

    func selectPreviousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = newMonth
        }
    }

    func selectNextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
            selectedMonth = newMonth
        }
    }

    func loadBadges() async {
        isLoading = true
        errorMessage = nil

        do {
            badges = try await badgeRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshBadges() async {
        await loadBadges()
    }
}
