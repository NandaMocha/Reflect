import Foundation

enum InsightDateGroup: Hashable, Comparable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older(Date)

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .older(let date): return date.monthYearFormatted
        }
    }

    static func group(for date: Date, calendar: Calendar = .current) -> InsightDateGroup {
        let today = calendar.startOfDay(for: Date())
        let insightDate = calendar.startOfDay(for: date)

        if insightDate == today {
            return .today
        } else if insightDate == calendar.date(byAdding: .day, value: -1, to: today) {
            return .yesterday
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
                  insightDate > weekAgo {
            return .thisWeek
        } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: today),
                  insightDate > monthAgo {
            return .thisMonth
        } else {
            return .older(insightDate)
        }
    }

    static func < (lhs: InsightDateGroup, rhs: InsightDateGroup) -> Bool {
        switch (lhs, rhs) {
        case (.today, _): return true
        case (_, .today): return false
        case (.yesterday, _): return true
        case (_, .yesterday): return false
        case (.thisWeek, _): return true
        case (_, .thisWeek): return false
        case (.thisMonth, _): return true
        case (_, .thisMonth): return false
        case (.older(let lhsDate), .older(let rhsDate)): return lhsDate > rhsDate
        }
    }
}
