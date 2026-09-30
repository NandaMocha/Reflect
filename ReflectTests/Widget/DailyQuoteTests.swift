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

    // MARK: - Pools

    @Test(arguments: DailyQuote.Tone.allCases)
    func eachPoolHasMoreVariationThanTheOldSplit(_ tone: DailyQuote.Tone) {
        // The old single pool had 35 quotes, about 12 per slot if split three ways.
        #expect(DailyQuote.pool(for: tone).count >= 15)
    }

    @Test func allIsEveryPoolCombined() {
        let combined = DailyQuote.Tone.allCases.flatMap { DailyQuote.pool(for: $0) }
        #expect(DailyQuote.all == combined)
        #expect(DailyQuote.all.count > 35)
    }

    @Test func everyQuoteHasAnAuthor() {
        for quote in DailyQuote.all {
            let author = quote.author?.trimmingCharacters(in: .whitespaces) ?? ""
            #expect(!author.isEmpty, "\"\(quote.text)\" has no author")
        }
    }

    @Test func noQuoteIsRepeated() {
        let texts = DailyQuote.all.map(\.text)
        #expect(Set(texts).count == texts.count)
    }

    // MARK: - Tone of day

    /// (hour, minute, tone) around every slot boundary.
    static let boundaries: [(Int, Int, DailyQuote.Tone)] = [
        (4, 59, .evening),
        (5, 0, .morning),
        (11, 59, .morning),
        (12, 0, .afternoon),
        (17, 59, .afternoon),
        (18, 0, .evening),
        (23, 59, .evening),
        (0, 0, .evening)
    ]

    @Test(arguments: boundaries)
    func toneFollowsTheHour(_ hour: Int, _ minute: Int, _ expected: DailyQuote.Tone) throws {
        let now = try date(2026, 5, 10, hour, minute)
        #expect(DailyQuote.Tone(for: now, calendar: calendar) == expected)
        #expect(DailyQuote.pool(for: expected).contains(DailyQuote.forDate(now, calendar: calendar)))
    }

    // MARK: - Stability within a slot

    @Test func sameQuoteThroughoutTheMorning() throws {
        let start = try date(2026, 5, 10, 5, 0)
        let end = try date(2026, 5, 10, 11, 59)
        #expect(DailyQuote.index(for: start, calendar: calendar) == DailyQuote.index(for: end, calendar: calendar))
        #expect(DailyQuote.forDate(start, calendar: calendar) == DailyQuote.forDate(end, calendar: calendar))
    }

    @Test func sameQuoteThroughoutTheAfternoon() throws {
        let start = try date(2026, 5, 10, 12, 0)
        let end = try date(2026, 5, 10, 17, 59)
        #expect(DailyQuote.forDate(start, calendar: calendar) == DailyQuote.forDate(end, calendar: calendar))
    }

    /// The evening runs past midnight, so 02:00 still shows the quote picked at 18:00 the day before.
    @Test func sameQuoteThroughoutTheEveningAcrossMidnight() throws {
        let start = try date(2026, 5, 10, 18, 0)
        let lateNight = try date(2026, 5, 11, 2, 0)
        let end = try date(2026, 5, 11, 4, 59)
        #expect(DailyQuote.forDate(start, calendar: calendar) == DailyQuote.forDate(lateNight, calendar: calendar))
        #expect(DailyQuote.forDate(start, calendar: calendar) == DailyQuote.forDate(end, calendar: calendar))
    }

    @Test func quoteChangesAtEachSlotBoundary() throws {
        let slots = try [
            date(2026, 5, 10, 4, 59), date(2026, 5, 10, 5, 0),
            date(2026, 5, 10, 11, 59), date(2026, 5, 10, 12, 0),
            date(2026, 5, 10, 17, 59), date(2026, 5, 10, 18, 0)
        ]
        for pair in stride(from: 0, to: slots.count, by: 2) {
            #expect(DailyQuote.forDate(slots[pair], calendar: calendar) != DailyQuote.forDate(slots[pair + 1], calendar: calendar))
        }
    }

    // MARK: - Rotation across days

    @Test(arguments: DailyQuote.Tone.allCases)
    func differentQuoteOnConsecutiveDaysInTheSameSlot(_ tone: DailyQuote.Tone) throws {
        let today = try date(2026, 5, 10, tone.startHour)
        let tomorrow = try date(2026, 5, 11, tone.startHour)
        #expect(DailyQuote.forDate(today, calendar: calendar) != DailyQuote.forDate(tomorrow, calendar: calendar))
    }

    @Test(arguments: DailyQuote.Tone.allCases)
    func showsEveryQuoteInThePoolBeforeRepeating(_ tone: DailyQuote.Tone) throws {
        let pool = DailyQuote.pool(for: tone)
        let first = try date(2026, 5, 10, tone.startHour)
        let shown = try (0..<pool.count).map { offset in
            let day = try #require(calendar.date(byAdding: .day, value: offset, to: first))
            return DailyQuote.forDate(day, calendar: calendar).text
        }
        #expect(Set(shown) == Set(pool.map(\.text)))

        let wrapped = try #require(calendar.date(byAdding: .day, value: pool.count, to: first))
        #expect(DailyQuote.forDate(wrapped, calendar: calendar) == DailyQuote.forDate(first, calendar: calendar))
    }

    /// Day numbers are counted continuously, so New Year's Day doesn't restart the rotation.
    @Test func rotationContinuesAcrossTheEndOfALeapYear() throws {
        let dayThreeSixtySix = try date(2028, 12, 31, 8)
        let newYear = try date(2029, 1, 1, 8)
        #expect(calendar.ordinality(of: .day, in: .year, for: dayThreeSixtySix) == 366)
        let count = DailyQuote.pool(for: .morning).count
        let last = DailyQuote.index(for: dayThreeSixtySix, calendar: calendar)
        let next = DailyQuote.index(for: newYear, calendar: calendar)
        #expect(DailyQuote.pool(for: .morning).indices.contains(last))
        #expect(next == (last + 1) % count)
    }
}
