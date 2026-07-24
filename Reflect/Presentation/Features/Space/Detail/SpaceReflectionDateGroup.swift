import Foundation

/// Date-based section grouping for a space's reflections (Today / Yesterday / This Week /
/// This Month / older-by-month), so the list is easy to scan by when things were posted.
/// Space-local (mirrors `InsightDateGroup`) to keep the feature self-contained.
enum SpaceReflectionDateGroup: Hashable, Comparable {
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

    static func group(for date: Date, calendar: Calendar = .current) -> SpaceReflectionDateGroup {
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)

        if day == today {
            return .today
        } else if day == calendar.date(byAdding: .day, value: -1, to: today) {
            return .yesterday
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today), day > weekAgo {
            return .thisWeek
        } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: today), day > monthAgo {
            return .thisMonth
        } else {
            // Key .older by month so different days of the same old month share one header.
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: day))
            return .older(monthStart ?? day)
        }
    }

    static func < (lhs: SpaceReflectionDateGroup, rhs: SpaceReflectionDateGroup) -> Bool {
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
