import Foundation
import SwiftData
import Observation

@Observable
final class BadgeGridViewModel {
    private let badgeRepository: BadgeRepositoryProtocol
    private let calendar = Calendar.current

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

    // MARK: - Month-based Badge Categories

    /// Streak badges for the selected month (monthlyStreak type)
    var streakBadgesForSelectedMonth: [Badge] {
        let components = calendar.dateComponents([.month, .year], from: selectedMonth)
        guard let month = components.month, let year = components.year else {
            return []
        }

        return badges.filter { badge in
            badge.type == .monthlyStreak && badge.month == month && badge.year == year
        }
    }

    /// All permanent achievement badges (earned once and kept forever)
    var permanentBadges: [Badge] {
        badges.filter { $0.type == .permanent }
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
        // Allow going forward to current month (or future months)
        return true
    }

    private var earliestBadgeMonth: Date? {
        let monthlyBadges = badges.filter { $0.type == .monthlyStreak && $0.month != nil && $0.year != nil }

        guard let firstBadge = monthlyBadges.first(
            where: { $0.month != nil && $0.year != nil }
        ) else { return nil }

        guard let month = firstBadge.month, let year = firstBadge.year else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month))
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
        self.badgeRepository = BadgeRepository(modelContext: modelContext)
    }

    init(badgeRepository: BadgeRepositoryProtocol) {
        self.badgeRepository = badgeRepository
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
