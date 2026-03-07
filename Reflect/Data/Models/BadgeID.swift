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

    var badgeDescription: String {
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
