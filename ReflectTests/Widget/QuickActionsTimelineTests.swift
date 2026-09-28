import Foundation
import Testing
@testable import Reflect

struct QuickActionsTimelineTests {
    private func calendar(_ timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        return calendar
    }

    private func date(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )))
    }

    @Test func entryCarriesTheDateAndItsDailyQuote() throws {
        let calendar = try calendar("UTC")
        let now = try date(calendar, 2026, 5, 10, 14, 30)
        let entry = QuickActionsTimeline.entry(for: now, calendar: calendar)
        #expect(entry.date == now)
        #expect(entry.quote == DailyQuote.forDate(now, calendar: calendar))
    }

    @Test func nextRefreshIsStartOfNextDayFromMidDay() throws {
        let calendar = try calendar("UTC")
        let now = try date(calendar, 2026, 5, 10, 12)
        let expected = try date(calendar, 2026, 5, 11)
        #expect(QuickActionsTimeline.nextRefreshDate(after: now, calendar: calendar) == expected)
    }

    @Test func nextRefreshIsStartOfNextDayFromLastSecond() throws {
        let calendar = try calendar("UTC")
        let now = try date(calendar, 2026, 5, 10, 23, 59, 59)
        let expected = try date(calendar, 2026, 5, 11)
        #expect(QuickActionsTimeline.nextRefreshDate(after: now, calendar: calendar) == expected)
    }

    @Test func nextRefreshFromMidnightIsTheFollowingMidnight() throws {
        let calendar = try calendar("UTC")
        let now = try date(calendar, 2026, 5, 10)
        let expected = try date(calendar, 2026, 5, 11)
        #expect(QuickActionsTimeline.nextRefreshDate(after: now, calendar: calendar) == expected)
    }

    /// 2026-03-08 in New York loses an hour at 02:00, so the day is 23 hours long.
    @Test func nextRefreshAcrossSpringForward() throws {
        let calendar = try calendar("America/New_York")
        let now = try date(calendar, 2026, 3, 8, 12)
        let expected = try date(calendar, 2026, 3, 9)
        let refresh = QuickActionsTimeline.nextRefreshDate(after: now, calendar: calendar)
        #expect(refresh == expected)
        #expect(refresh.timeIntervalSince(calendar.startOfDay(for: now)) == 23 * 3_600)
    }

    /// 2026-11-01 in New York repeats 01:00 to 02:00, so the day is 25 hours long.
    @Test func nextRefreshAcrossFallBack() throws {
        let calendar = try calendar("America/New_York")
        let now = try date(calendar, 2026, 11, 1, 23, 59, 59)
        let expected = try date(calendar, 2026, 11, 2)
        let refresh = QuickActionsTimeline.nextRefreshDate(after: now, calendar: calendar)
        #expect(refresh == expected)
        #expect(refresh.timeIntervalSince(calendar.startOfDay(for: now)) == 25 * 3_600)
    }
}
