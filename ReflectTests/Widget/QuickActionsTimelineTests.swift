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

    /// (now hour, minute, second) -> (refresh day offset, refresh hour)
    @Test(arguments: [
        ((0, 0, 0), (0, 5)),
        ((4, 59, 59), (0, 5)),
        ((5, 0, 0), (0, 12)),
        ((8, 30, 0), (0, 12)),
        ((11, 59, 59), (0, 12)),
        ((12, 0, 0), (0, 18)),
        ((17, 59, 59), (0, 18)),
        ((18, 0, 0), (1, 5)),
        ((23, 59, 59), (1, 5))
    ])
    func nextRefreshIsTheNextSlotBoundary(_ now: (Int, Int, Int), _ expected: (Int, Int)) throws {
        let calendar = try calendar("UTC")
        let start = try date(calendar, 2026, 5, 10, now.0, now.1, now.2)
        let refresh = try date(calendar, 2026, 5, 10 + expected.0, expected.1)
        #expect(QuickActionsTimeline.nextRefreshDate(after: start, calendar: calendar) == refresh)
    }

    @Test func refreshesThreeTimesADay() throws {
        let calendar = try calendar("UTC")
        var cursor = try date(calendar, 2026, 5, 10, 5)
        let end = try date(calendar, 2026, 5, 11, 5)
        var refreshes = 0
        while cursor < end {
            cursor = QuickActionsTimeline.nextRefreshDate(after: cursor, calendar: calendar)
            refreshes += 1
        }
        #expect(refreshes == 3)
        #expect(cursor == end)
    }

    @Test func eachRefreshStartsANewTone() throws {
        let calendar = try calendar("UTC")
        let now = try date(calendar, 2026, 5, 10, 9)
        let refresh = QuickActionsTimeline.nextRefreshDate(after: now, calendar: calendar)
        let lastSecond = refresh.addingTimeInterval(-1)
        #expect(DailyQuote.Tone(for: lastSecond, calendar: calendar) == DailyQuote.Tone(for: now, calendar: calendar))
        #expect(DailyQuote.Tone(for: refresh, calendar: calendar) != DailyQuote.Tone(for: now, calendar: calendar))
    }

    /// 2026-03-08 in New York skips 02:00 to 03:00, so the night slot is an hour shorter.
    @Test func nextRefreshAcrossSpringForward() throws {
        let calendar = try calendar("America/New_York")
        let evening = try date(calendar, 2026, 3, 7, 20)
        let morning = try date(calendar, 2026, 3, 8, 5)
        let refresh = QuickActionsTimeline.nextRefreshDate(after: evening, calendar: calendar)
        #expect(refresh == morning)
        #expect(refresh.timeIntervalSince(evening) == 8 * 3_600)

        let afterMidnight = try date(calendar, 2026, 3, 8, 0, 30)
        #expect(QuickActionsTimeline.nextRefreshDate(after: afterMidnight, calendar: calendar) == morning)
        #expect(morning.timeIntervalSince(afterMidnight) == 3.5 * 3_600)
    }

    /// 2026-11-01 in New York repeats 01:00 to 02:00, so the night slot is an hour longer.
    @Test func nextRefreshAcrossFallBack() throws {
        let calendar = try calendar("America/New_York")
        let evening = try date(calendar, 2026, 10, 31, 20)
        let morning = try date(calendar, 2026, 11, 1, 5)
        let refresh = QuickActionsTimeline.nextRefreshDate(after: evening, calendar: calendar)
        #expect(refresh == morning)
        #expect(refresh.timeIntervalSince(evening) == 10 * 3_600)

        let afterMidnight = try date(calendar, 2026, 11, 1, 0, 30)
        #expect(QuickActionsTimeline.nextRefreshDate(after: afterMidnight, calendar: calendar) == morning)
        #expect(morning.timeIntervalSince(afterMidnight) == 5.5 * 3_600)
    }
}
