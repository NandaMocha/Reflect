import Foundation
import SwiftData
import Observation

@Observable
final class BadgeGridViewModel {
    private let badgeRepository: BadgeRepositoryProtocol
    let modelContext: ModelContext

    var badges: [Badge] = []
    var isLoading: Bool = false
    var errorMessage: String?

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

    /// The single most recently achieved badge
    var latestAchievement: Badge? {
        let unlockedBadges = badges.filter { $0.isUnlocked }
        return unlockedBadges
            .sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
            .first
    }

    // MARK: - Badge Categories

    /// All permanent achievement badges (all badges are now permanent after removing streaks)
    var permanentBadges: [Badge] {
        badges  // All badges are permanent now
    }

    // MARK: - Stats

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
