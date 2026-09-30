import Foundation

// MARK: - Daily Quote

/// A short, bundled quote shown on the medium widget. The lists ship with the extension (no
/// network, no App Group). Each time of day has its own pool with a matching tone, and the quote
/// is chosen deterministically from the date, so it is stable within a slot and changes at each
/// slot boundary.
struct DailyQuote: Equatable {
    let text: String
    let author: String?

    // MARK: - Tone of Day

    /// The three slots of the day. The evening runs past midnight until 05:00.
    enum Tone: CaseIterable, Sendable {
        case morning, afternoon, evening

        /// Hour the slot starts, in the calendar's time zone.
        var startHour: Int {
            switch self {
            case .morning: 5
            case .afternoon: 12
            case .evening: 18
            }
        }

        init(for date: Date, calendar: Calendar = .current) {
            switch calendar.component(.hour, from: date) {
            case Tone.morning.startHour..<Tone.afternoon.startHour: self = .morning
            case Tone.afternoon.startHour..<Tone.evening.startHour: self = .afternoon
            default: self = .evening
            }
        }
    }

    // MARK: - Pools

    /// Fresh start, a new page, a new day. Kept short so they fit the medium widget's quote column.
    static let morning: [DailyQuote] = [
        DailyQuote(text: "Begin at once to live, and count each separate day as a separate life.", author: "Seneca"),
        DailyQuote(text: "Write it on your heart that every day is the best day in the year.", author: "Ralph Waldo Emerson"),
        DailyQuote(text: "With the new day comes new strength and new thoughts.", author: "Eleanor Roosevelt"),
        DailyQuote(text: "This is a wonderful day. I've never seen this one before.", author: "Maya Angelou"),
        DailyQuote(text: "The beginning is the most important part of the work.", author: "Plato"),
        DailyQuote(text: "Well begun is half done.", author: "Aristotle"),
        DailyQuote(text: "The journey of a thousand miles begins with one step.", author: "Lao Tzu"),
        DailyQuote(text: "You don't have to see the whole staircase, just take the first step.", author: "Martin Luther King Jr."),
        DailyQuote(text: "Start where you are. Use what you have. Do what you can.", author: "Arthur Ashe"),
        DailyQuote(text: "What you do today can improve all your tomorrows.", author: "Ralph Marston"),
        DailyQuote(text: "Live as if you were to die tomorrow. Learn as if you were to live forever.", author: "Gandhi"),
        DailyQuote(text: "Wisdom begins in wonder.", author: "Socrates"),
        DailyQuote(text: "Curiosity is the wick in the candle of learning.", author: "William Arthur Ward"),
        DailyQuote(text: "The mind is not a vessel to be filled but a fire to be kindled.", author: "Plutarch"),
        DailyQuote(text: "Develop a passion for learning. If you do, you will never cease to grow.", author: "Anthony J. D'Angelo"),
        DailyQuote(text: "The expert in anything was once a beginner.", author: "Helen Hayes")
    ]

    /// Keep going, keep fighting, thrive.
    static let afternoon: [DailyQuote] = [
        DailyQuote(text: "It does not matter how slowly you go as long as you do not stop.", author: "Confucius"),
        DailyQuote(text: "Energy and persistence conquer all things.", author: "Benjamin Franklin"),
        DailyQuote(text: "Our greatest glory is not in never falling, but in rising every time we fall.", author: "Oliver Goldsmith"),
        DailyQuote(text: "If you're going through hell, keep going.", author: "Winston Churchill"),
        DailyQuote(text: "Perseverance is not a long race; it is many short races one after the other.", author: "Walter Elliot"),
        DailyQuote(text: "The harder the conflict, the more glorious the triumph.", author: "Thomas Paine"),
        DailyQuote(text: "It always seems impossible until it's done.", author: "Nelson Mandela"),
        DailyQuote(text: "Nothing in the world can take the place of persistence.", author: "Calvin Coolidge"),
        DailyQuote(text: "I have not failed. I've just found 10,000 ways that won't work.", author: "Thomas Edison"),
        DailyQuote(text: "Believe you can and you're halfway there.", author: "Theodore Roosevelt"),
        DailyQuote(text: "Small daily improvements are the key to staggering long-term results.", author: "Robin Sharma"),
        DailyQuote(text: "Life begins at the end of your comfort zone.", author: "Neale Donald Walsch"),
        DailyQuote(text: "Turn your wounds into wisdom.", author: "Oprah Winfrey"),
        DailyQuote(text: "Tell me and I forget, teach me and I may remember, involve me and I learn.", author: "Benjamin Franklin"),
        DailyQuote(text: "The beautiful thing about learning is that no one can take it away from you.", author: "B.B. King"),
        DailyQuote(text: "What we learn with pleasure we never forget.", author: "Alfred Mercier"),
        DailyQuote(text: "Learning never exhausts the mind.", author: "Leonardo da Vinci"),
        DailyQuote(text: "The capacity to learn is a gift; the ability to learn is a skill.", author: "Brian Herbert"),
        DailyQuote(text: "The more that you read, the more things you will know.", author: "Dr. Seuss")
    ]

    /// Reflect on today, trust that it happened for a reason, look toward tomorrow.
    static let evening: [DailyQuote] = [
        DailyQuote(text: "We do not learn from experience. We learn from reflecting on experience.", author: "John Dewey"),
        DailyQuote(text: "Reflection turns experience into insight.", author: "John C. Maxwell"),
        DailyQuote(text: "The unexamined life is not worth living.", author: "Socrates"),
        DailyQuote(text: "Knowing yourself is the beginning of all wisdom.", author: "Aristotle"),
        DailyQuote(text: "The only true wisdom is in knowing you know nothing.", author: "Socrates"),
        DailyQuote(text: "Everything that happens happens as it should.", author: "Marcus Aurelius"),
        DailyQuote(text: "Life can only be understood backwards; but it must be lived forwards.", author: "Søren Kierkegaard"),
        DailyQuote(text: "Nothing is a waste of time if you use the experience wisely.", author: "Auguste Rodin"),
        DailyQuote(text: "Reflect on your present blessings, of which every person has many.", author: "Charles Dickens"),
        DailyQuote(text: "By three methods we may learn wisdom: reflection, imitation, and experience.", author: "Confucius"),
        DailyQuote(text: "He who learns but does not think is lost.", author: "Confucius"),
        DailyQuote(text: "Study the past if you would define the future.", author: "Confucius"),
        DailyQuote(text: "Doubt is the origin of wisdom.", author: "René Descartes"),
        DailyQuote(text: "Learn from yesterday, live for today, hope for tomorrow.", author: "Albert Einstein"),
        DailyQuote(text: "Finish each day and be done with it. Tomorrow is a new day.", author: "Ralph Waldo Emerson"),
        DailyQuote(text: "Tomorrow is a new day with no mistakes in it yet.", author: "L.M. Montgomery")
    ]

    /// Every pool in slot order: morning, afternoon, evening.
    static let all: [DailyQuote] = Tone.allCases.flatMap { DailyQuote.pool(for: $0) }

    static func pool(for tone: Tone) -> [DailyQuote] {
        switch tone {
        case .morning: morning
        case .afternoon: afternoon
        case .evening: evening
        }
    }

    // MARK: - Selection

    /// Deterministic pick for the slot containing `date`: stable within the slot, and each slot
    /// walks its own pool one quote per day.
    static func forDate(_ date: Date, calendar: Calendar = .current) -> DailyQuote {
        let pool = Self.pool(for: Tone(for: date, calendar: calendar))
        guard !pool.isEmpty else { return DailyQuote(text: "Reflection turns experience into insight.", author: "John C. Maxwell") }
        return pool[index(for: date, calendar: calendar)]
    }

    /// Index into the pool for `date`'s slot. Days are counted continuously (not by day of year)
    /// so the rotation doesn't restart on New Year's Day. The hours after midnight belong to the
    /// previous day's evening, so the evening quote doesn't change at midnight.
    static func index(for date: Date, calendar: Calendar = .current) -> Int {
        let count = max(Self.pool(for: Tone(for: date, calendar: calendar)).count, 1)
        let isAfterMidnight = calendar.component(.hour, from: date) < Tone.morning.startHour
        let slotDay = isAfterMidnight ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        let day = calendar.ordinality(of: .day, in: .era, for: slotDay) ?? 1
        return (day - 1) % count
    }
}
