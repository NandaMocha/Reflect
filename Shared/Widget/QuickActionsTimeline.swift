import Foundation

/// One timeline entry for the Quick Actions widget. `TimelineEntry` conformance lives in the
/// widget extension so this file stays free of WidgetKit.
struct QuickActionsEntry {
    let date: Date
    let quote: DailyQuote
}

/// Pure timeline logic for the Quick Actions widget, kept out of the provider so it is testable.
enum QuickActionsTimeline {
    static func entry(for date: Date, calendar: Calendar = .current) -> QuickActionsEntry {
        QuickActionsEntry(date: date, quote: DailyQuote.forDate(date, calendar: calendar))
    }

    /// Start of the day after `date`, so the daily quote turns over at midnight. Uses the day's
    /// interval rather than adding 86,400 seconds so 23 and 25 hour DST days land on midnight.
    static func nextRefreshDate(after date: Date, calendar: Calendar = .current) -> Date {
        if let end = calendar.dateInterval(of: .day, for: date)?.end {
            return end
        }
        return calendar.startOfDay(for: date.addingTimeInterval(86_400))
    }
}
