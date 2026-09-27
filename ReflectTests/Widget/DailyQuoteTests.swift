import Foundation
import Testing
@testable import Reflect

struct DailyQuoteTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    @Test func sameQuoteForTwoTimesOnTheSameDay() throws {
        let morning = try date(2026, 5, 10, 0, 1)
        let night = try date(2026, 5, 10, 23, 59)
        #expect(DailyQuote.index(for: morning, calendar: calendar) == DailyQuote.index(for: night, calendar: calendar))
        #expect(DailyQuote.forDate(morning, calendar: calendar) == DailyQuote.forDate(night, calendar: calendar))
    }

    @Test func differentIndexOnConsecutiveDays() throws {
        let today = try date(2026, 5, 10)
        let tomorrow = try date(2026, 5, 11)
        #expect(DailyQuote.index(for: today, calendar: calendar) != DailyQuote.index(for: tomorrow, calendar: calendar))
    }

    @Test func wrapsAroundAfterEveryQuoteWasShown() throws {
        let first = try date(2026, 1, 1)
        let wrapped = try #require(calendar.date(byAdding: .day, value: DailyQuote.all.count, to: first))
        #expect(DailyQuote.index(for: first, calendar: calendar) == 0)
        #expect(DailyQuote.index(for: wrapped, calendar: calendar) == 0)
        #expect(DailyQuote.forDate(wrapped, calendar: calendar) == DailyQuote.all[0])
    }

    @Test func lastDayOfALeapYearStaysInRange() throws {
        let dayThreeSixtySix = try date(2028, 12, 31)
        #expect(calendar.ordinality(of: .day, in: .year, for: dayThreeSixtySix) == 366)
        let index = DailyQuote.index(for: dayThreeSixtySix, calendar: calendar)
        #expect(DailyQuote.all.indices.contains(index))
        #expect(DailyQuote.forDate(dayThreeSixtySix, calendar: calendar) == DailyQuote.all[index])
    }
}
