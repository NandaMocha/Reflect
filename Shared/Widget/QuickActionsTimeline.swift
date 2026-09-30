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

    /// Start of the next tone slot after `date` (05:00, 12:00 or 18:00), so the quote changes
    /// three times a day. Matches wall-clock hours through the calendar rather than adding
    /// seconds, so slots that span a DST change still end on the hour.
    static func nextRefreshDate(after date: Date, calendar: Calendar = .current) -> Date {
        let boundaries = DailyQuote.Tone.allCases.compactMap { tone in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: tone.startHour, minute: 0, second: 0),
                matchingPolicy: .nextTime
            )
        }
        if let next = boundaries.min() {
            return next
        }
        return calendar.startOfDay(for: date.addingTimeInterval(86_400))
    }
}
