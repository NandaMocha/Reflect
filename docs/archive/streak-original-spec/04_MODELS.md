# Data Models - Copy-Paste Ready Code

---

## 📋 BadgeID Enum

Copy this to `Domain/Models/BadgeID.swift`

```swift
import Foundation

enum BadgeID: String, CaseIterable, Identifiable {
    // Repeated Badges
    case threeDay = "3day-streak"
    case sevenDay = "7day-streak"
    case fourteenDay = "14day-streak"
    case thirtyDay = "30day-streak"
    case firstDayMonth = "first-day-month"

    // Permanent Badges
    case firstReflection = "first-reflection"
    case fullMonth = "full-month"
    case halfMonth = "half-month"
    case sixMonthConsistency = "6month-consistency"
    case twelveMonthConsistency = "12month-consistency"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .threeDay: return "3-Day Streak"
        case .sevenDay: return "7-Day Streak"
        case .fourteenDay: return "14-Day Streak"
        case .thirtyDay: return "30-Day Streak"
        case .firstDayMonth: return "Monthly Start"
        case .firstReflection: return "First Reflection"
        case .fullMonth: return "Full Month"
        case .halfMonth: return "Half Month"
        case .sixMonthConsistency: return "6-Month Consistency"
        case .twelveMonthConsistency: return "12-Month Consistency"
        }
    }

    var description: String {
        switch self {
        case .threeDay: return "Reflect for 3 consecutive days"
        case .sevenDay: return "Reflect for 7 consecutive days"
        case .fourteenDay: return "Reflect for 14 consecutive days"
        case .thirtyDay: return "Reflect for 30 consecutive days"
        case .firstDayMonth: return "Create a reflection on the 1st day of the month"
        case .firstReflection: return "Create your first reflection"
        case .fullMonth: return "30 reflections in a calendar month"
        case .halfMonth: return "14+ reflections in a calendar month"
        case .sixMonthConsistency: return "At least 1 reflection in each of last 6 months"
        case .twelveMonthConsistency: return "At least 1 reflection in each of last 12 months"
        }
    }

    var icon: String {
        switch self {
        case .threeDay: return "🔥"
        case .sevenDay: return "🔥🔥"
        case .fourteenDay: return "🔥🔥🔥"
        case .thirtyDay: return "🔥🔥🔥🔥"
        case .firstDayMonth: return "🌅"
        case .firstReflection: return "🌟"
        case .fullMonth: return "📅"
        case .halfMonth: return "📅✨"
        case .sixMonthConsistency: return "🏆"
        case .twelveMonthConsistency: return "👑"
        }
    }

    var badgeType: BadgeType {
        switch self {
        case .threeDay, .sevenDay, .fourteenDay, .thirtyDay, .firstDayMonth:
            return .repeatedStreak
        default:
            return .permanent
        }
    }

    static var all: [BadgeID] {
        allCases
    }
}

enum BadgeType: String, Codable {
    case repeatedStreak = "repeated_streak"
    case permanent = "permanent"
}
```

---

## 🏅 Badge Model

Copy to `Domain/Models/Badge.swift`

```swift
import Foundation
import SwiftData

@Model
final class Badge {
    @Attribute(.unique) var id: String

    var type: BadgeType
    var name: String
    var description: String
    var icon: String

    // Unlock tracking
    var isUnlocked: Bool = false
    var unlockedAt: Date?
    var unlockedCount: Int = 0  // For repeated badges

    // Metadata
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: String,
        type: BadgeType,
        name: String,
        description: String,
        icon: String
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.description = description
        self.icon = icon
    }

    // Convenience initializer
    convenience init(from badgeID: BadgeID) {
        self.init(
            id: badgeID.rawValue,
            type: badgeID.badgeType,
            name: badgeID.displayName,
            description: badgeID.description,
            icon: badgeID.icon
        )
    }

    // MARK: - Helper Methods

    func unlock() {
        isUnlocked = true
        unlockedAt = Date()
        unlockedCount += 1
        updatedAt = Date()
    }

    var isNew: Bool {
        guard let unlockedAt = unlockedAt else { return false }
        return Calendar.current.isDateInToday(unlockedAt)
    }
}
```

---

## 🔥 StreakData Model

Copy to `Domain/Models/StreakData.swift`

```swift
import Foundation
import SwiftData

@Model
final class StreakData {
    @Attribute(.unique) var id: UUID = UUID()

    // Current streak tracking
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastSubmissionDate: Date?
    var streakStartDate: Date?

    // Metadata
    var totalReflections: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    // MARK: - Helper Methods

    var isStreakActive: Bool {
        guard let lastDate = lastSubmissionDate else { return false }
        let daysSinceLastSubmission = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastDate),
            to: Calendar.current.startOfDay(for: .now)
        ).day ?? 0
        return daysSinceLastSubmission <= 1
    }

    var daysUntilMilestone: Int? {
        let milestones = [3, 7, 14, 30]
        for milestone in milestones {
            if currentStreak < milestone {
                return milestone - currentStreak
            }
        }
        return nil
    }
}
```

---

## 📅 MonthlyAchievement Model

Copy to `Domain/Models/MonthlyAchievement.swift`

```swift
import Foundation
import SwiftData

@Model
final class MonthlyAchievement {
    @Attribute(.unique) var id: String  // Format: "YYYY-MM"

    var year: Int
    var month: Int  // 1-12

    var reflectionCount: Int = 0
    var hasFullMonth: Bool = false      // 30+
    var hasHalfMonth: Bool = false      // 14+
    var hasAnyReflection: Bool = false  // 1+
    var hasFirstDayReflection: Bool = false

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(year: Int, month: Int) {
        self.id = String(format: "%04d-%02d", year, month)
        self.year = year
        self.month = month
    }

    // MARK: - Computed Properties

    var yearMonthString: String {
        String(format: "%04d-%02d", year, month)
    }

    var displayName: String {
        let dateComponents = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: dateComponents) else {
            return yearMonthString
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var progressToFullMonth: Double {
        min(Double(reflectionCount) / 30.0, 1.0)
    }

    var progressToHalfMonth: Double {
        min(Double(reflectionCount) / 14.0, 1.0)
    }
}
```

---

## ⭐ StreakStats Model (Non-persistent)

Copy to `Domain/Models/StreakStats.swift`

```swift
import Foundation

struct StreakStats {
    let currentStreak: Int
    let longestStreak: Int
    let lastSubmissionDate: Date?
    let streakStartDate: Date?
    let totalReflections: Int
    let isStreakActiveToday: Bool
    let daysUntilNextMilestone: Int?
    let nextMilestoneValue: Int?

    // MARK: - Computed Properties

    var streakPercentageToNext: Double {
        guard let nextMilestone = nextMilestoneValue else { return 1.0 }
        let percentage = Double(currentStreak) / Double(nextMilestone)
        return min(percentage, 1.0)
    }

    var nextMilestoneName: String {
        guard let next = nextMilestoneValue else { return "Ongoing" }
        return "\(next)-Day Streak"
    }

    var isStreakBroken: Bool {
        currentStreak == 0 && totalReflections > 0
    }
}
```

---

## 📊 MonthHeatmapData Model (Non-persistent)

Copy to `Domain/Models/MonthHeatmapData.swift`

```swift
import Foundation

struct MonthHeatmapData {
    let year: Int
    let month: Int
    let reflectionCountByDay: [Int: Int]  // day -> count

    // MARK: - Computed Properties

    var displayMonth: String {
        let dateComponents = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: dateComponents) else {
            return "\(month)/\(year)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var daysInMonth: Int {
        let dateComponents = DateComponents(year: year, month: month)
        guard let date = Calendar.current.date(from: dateComponents),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else {
            return 31
        }
        return range.count
    }

    var weekGrid: [[Int?]] {
        let firstDay = DateComponents(year: year, month: month, day: 1)
        guard let firstDate = Calendar.current.date(from: firstDay) else {
            return []
        }

        let firstWeekday = Calendar.current.component(.weekday, from: firstDate) - 1
        let totalDays = daysInMonth

        var grid: [[Int?]] = []
        var week: [Int?] = Array(repeating: nil, count: firstWeekday)

        for day in 1...totalDays {
            week.append(day)
            if week.count == 7 {
                grid.append(week)
                week = []
            }
        }

        if !week.isEmpty {
            while week.count < 7 {
                week.append(nil)
            }
            grid.append(week)
        }

        return grid
    }

    func colorForDay(_ day: Int) -> HeatmapColor {
        let count = reflectionCountByDay[day] ?? 0
        switch count {
        case 0:
            return .empty
        case 1:
            return .light
        case 2...3:
            return .medium
        default:
            return .dark
        }
    }

    enum HeatmapColor {
        case empty      // Gray
        case light      // Light green
        case medium     // Medium green
        case dark       // Dark green

        var backgroundColor: String {
            switch self {
            case .empty: return "#EEEEEE"
            case .light: return "#C6E48B"
            case .medium: return "#7BC96F"
            case .dark: return "#239A3B"
            }
        }
    }
}
```

---

## 🎉 BadgeUnlockEvent Model (Non-persistent)

Copy to `Domain/Models/BadgeUnlockEvent.swift`

```swift
import Foundation

struct BadgeUnlockEvent {
    let badge: Badge
    let isNewUnlock: Bool
    let unlockedCount: Int
    let celebrationTrigger: CelebrationTrigger

    enum CelebrationTrigger {
        case confetti
        case sparkles
        case fireworks
        case maximum
        case none
    }
}
```

---

## 🔧 Reflection Model Enhancement

Add these properties to existing `Reflection.swift`:

```swift
@Model
final class Reflection {
    // ... existing properties ...

    // STREAK PROPERTIES (NEW)
    var submittedDate: Date?       // When user submitted for streak
    var isStreakSubmission: Bool = false  // Flag for streak counting

    // HELPER (NEW)
    var isSubmittedToday: Bool {
        guard let submitted = submittedDate else { return false }
        return Calendar.current.isDateInToday(submitted)
    }

    var isFirstDayOfMonth: Bool {
        guard let submitted = submittedDate else { return false }
        return Calendar.current.component(.day, from: submitted) == 1
    }
}
```

---

## 📝 Quick Reference: What Goes Where

| File | Location |
|------|----------|
| BadgeID.swift | `Domain/Models/` |
| Badge.swift | `Domain/Models/` |
| StreakData.swift | `Domain/Models/` |
| MonthlyAchievement.swift | `Domain/Models/` |
| StreakStats.swift | `Domain/Models/` |
| MonthHeatmapData.swift | `Domain/Models/` |
| BadgeUnlockEvent.swift | `Domain/Models/` |
| Reflection.swift | Update existing |

---

Ready for implementation guide? See **05_IMPLEMENTATION.md**
