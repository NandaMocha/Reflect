import Foundation
import SwiftData

@Model
final class Badge {
    @Attribute(.unique) var id: String

    var type: BadgeType
    var category: BadgeCategory? = nil  // Optional for migration compatibility
    var name: String
    var badgeDescription: String
    var icon: String

    // For monthly streak badges - tracks which month/year this badge belongs to
    var month: Int? = nil       // 1-12, nil for permanent badges
    var year: Int? = nil        // e.g., 2025, nil for permanent badges

    // Unlock tracking
    var isUnlocked: Bool = false
    var unlockedAt: Date?
    var unlockedCount: Int = 0

    // Metadata
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: String,
        type: BadgeType,
        category: BadgeCategory,
        name: String,
        badgeDescription: String,
        icon: String,
        month: Int? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.category = category
        self.name = name
        self.badgeDescription = badgeDescription
        self.icon = icon
        self.month = month
        self.year = year
    }

    // Convenience initializer for permanent badges
    convenience init(from badgeID: BadgeID) {
        self.init(
            id: badgeID.rawValue,
            type: badgeID.badgeType,
            category: badgeID.badgeCategory,
            name: badgeID.displayName,
            badgeDescription: badgeID.badgeDescription,
            icon: badgeID.icon,
            month: nil,
            year: nil
        )
    }

    // Convenience initializer for monthly streak badges
    convenience init(from badgeID: BadgeID, month: Int, year: Int) {
        let uniqueId = "\(badgeID.rawValue)-\(year)-\(month)"
        self.init(
            id: uniqueId,
            type: badgeID.badgeType,
            category: badgeID.badgeCategory,
            name: badgeID.displayName,
            badgeDescription: badgeID.badgeDescription,
            icon: badgeID.icon,
            month: month,
            year: year
        )
    }

    // MARK: - Helper Methods

    func unlock() {
        isUnlocked = true
        if unlockedAt == nil {
            unlockedAt = Date()
        }
        unlockedCount += 1
        updatedAt = Date()
    }

    var isNew: Bool {
        guard let unlockedAt = unlockedAt else { return false }
        return Calendar.current.isDateInToday(unlockedAt)
    }

    // Check if this is a monthly streak badge
    var isMonthlyStreakBadge: Bool {
        type == .monthlyStreak && month != nil && year != nil
    }

    // Get month-year string for display
    var monthYearString: String? {
        guard let month = month, let year = year else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let date = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? Date()
        return formatter.string(from: date)
    }

    // MARK: - Helper Methods

    var howToAchieve: String {
        // Try to match BadgeID and get its requirement description
        if let badgeID = BadgeID.allCases.first(where: { $0.rawValue == id }) {
            return badgeID.requirementDescription
        }

        // Fallback to description if no match found
        return badgeDescription
    }
}
