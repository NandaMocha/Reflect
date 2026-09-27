import Foundation

// MARK: - Daily Quote

/// A short, bundled reflection prompt shown on the medium widget. The list ships with the
/// extension (no network, no App Group) and the day's quote is chosen deterministically from
/// the date, so it is stable within a day and rotates at midnight.
struct DailyQuote: Equatable {
    let text: String
    let author: String?

    /// Curated, deliberately short so they fit the medium widget's quote column.
    static let all: [DailyQuote] = [
        DailyQuote(text: "The unexamined life is not worth living.", author: "Socrates"),
        DailyQuote(text: "We do not learn from experience. We learn from reflecting on experience.", author: "John Dewey"),
        DailyQuote(text: "Knowing yourself is the beginning of all wisdom.", author: "Aristotle"),
        DailyQuote(text: "Live as if you were to die tomorrow. Learn as if you were to live forever.", author: "Gandhi"),
        DailyQuote(text: "What we learn with pleasure we never forget.", author: "Alfred Mercier"),
        DailyQuote(text: "The only true wisdom is in knowing you know nothing.", author: "Socrates"),
        DailyQuote(text: "Learning never exhausts the mind.", author: "Leonardo da Vinci"),
        DailyQuote(text: "Reflection turns experience into insight.", author: nil),
        DailyQuote(text: "Small daily improvements are the key to staggering long-term results.", author: nil),
        DailyQuote(text: "An investment in knowledge pays the best interest.", author: "Benjamin Franklin"),
        DailyQuote(text: "The mind is not a vessel to be filled but a fire to be kindled.", author: "Plutarch"),
        DailyQuote(text: "Wisdom begins in wonder.", author: "Socrates"),
        DailyQuote(text: "Every day is a chance to learn something new.", author: nil),
        DailyQuote(text: "Tell me and I forget, teach me and I may remember, involve me and I learn.", author: "Benjamin Franklin"),
        DailyQuote(text: "Change is the end result of all true learning.", author: "Leo Buscaglia"),
        DailyQuote(text: "Growth begins at the edge of your comfort zone.", author: nil),
        DailyQuote(text: "The beautiful thing about learning is that no one can take it away from you.", author: "B.B. King"),
        DailyQuote(text: "Mistakes are proof that you are trying.", author: nil),
        DailyQuote(text: "Develop a passion for learning. If you do, you will never cease to grow.", author: "Anthony J. D'Angelo"),
        DailyQuote(text: "What did today teach you?", author: nil),
        DailyQuote(text: "A little progress each day adds up to big results.", author: nil),
        DailyQuote(text: "He who learns but does not think is lost.", author: "Confucius"),
        DailyQuote(text: "The capacity to learn is a gift; the ability to learn is a skill.", author: "Brian Herbert"),
        DailyQuote(text: "Study the past if you would define the future.", author: "Confucius"),
        DailyQuote(text: "Curiosity is the wick in the candle of learning.", author: "William Arthur Ward"),
        DailyQuote(text: "Reflect on your present blessings, of which every person has many.", author: "Charles Dickens"),
        DailyQuote(text: "You don't have to see the whole staircase, just take the first step.", author: "Martin Luther King Jr."),
        DailyQuote(text: "Learning is a treasure that will follow its owner everywhere.", author: nil),
        DailyQuote(text: "Doubt is the origin of wisdom.", author: "René Descartes"),
        DailyQuote(text: "The expert in anything was once a beginner.", author: nil),
        DailyQuote(text: "Turn your wounds into wisdom.", author: "Oprah Winfrey"),
        DailyQuote(text: "By three methods we may learn wisdom: reflection, imitation, and experience.", author: "Confucius"),
        DailyQuote(text: "The more that you read, the more things you will know.", author: "Dr. Seuss"),
        DailyQuote(text: "Learn from yesterday, live for today, hope for tomorrow.", author: "Albert Einstein"),
        DailyQuote(text: "Nothing is a waste of time if you use the experience wisely.", author: "Auguste Rodin"),
        DailyQuote(text: "Slow down and reflect — that is where insight lives.", author: nil)
    ]

    /// Deterministic pick for a given day (stable within the day, rotates at midnight).
    static func forDate(_ date: Date, calendar: Calendar = .current) -> DailyQuote {
        guard !all.isEmpty else { return DailyQuote(text: "What did today teach you?", author: nil) }
        return all[index(for: date, calendar: calendar)]
    }

    /// Index into `all` for the day of the year of `date`, wrapping after `all.count` days.
    static func index(for date: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return (day - 1) % max(all.count, 1)
    }
}
