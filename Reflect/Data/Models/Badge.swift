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
        icon: String
    ) {
        self.id = id
        self.type = type
        self.category = category
        self.name = name
        self.badgeDescription = badgeDescription
        self.icon = icon
    }

    // Convenience initializer for badges
    convenience init(from badgeID: BadgeID) {
        self.init(
            id: badgeID.rawValue,
            type: badgeID.badgeType,
            category: badgeID.badgeCategory,
            name: badgeID.displayName,
            badgeDescription: badgeID.badgeDescription,
            icon: badgeID.icon
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

    var howToAchieve: String {
        // Try to match BadgeID and get its requirement description
        if let badgeID = BadgeID.allCases.first(where: { $0.rawValue == id }) {
            return badgeID.requirementDescription
        }

        // Fallback to description if no match found
        return badgeDescription
    }
}
