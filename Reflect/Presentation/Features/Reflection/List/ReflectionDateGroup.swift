import Foundation

enum ReflectionDateGroup: Hashable, Comparable {
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

    static func < (lhs: ReflectionDateGroup, rhs: ReflectionDateGroup) -> Bool {
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
