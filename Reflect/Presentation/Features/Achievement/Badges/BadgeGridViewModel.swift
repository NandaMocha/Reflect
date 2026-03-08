import Foundation
import SwiftData
import Observation

@Observable
final class BadgeGridViewModel {
    private let badgeRepository: BadgeRepositoryProtocol

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

    init(modelContext: ModelContext) {
        self.badgeRepository = BadgeRepository(modelContext: modelContext)
    }

    init(badgeRepository: BadgeRepositoryProtocol) {
        self.badgeRepository = badgeRepository
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
