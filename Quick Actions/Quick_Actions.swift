//
//  Quick_Actions.swift
//  Quick Actions
//
//  Reflect Widget - Quick access to create reflections
//

import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct QuickActionsEntry: TimelineEntry {
    let date: Date
    let quote: DailyQuote
}

// MARK: - Daily Quote

/// A short, bundled reflection prompt shown on the medium widget. The list ships with the
/// extension (no network, no App Group) and the day's quote is chosen deterministically from
/// the date, so it is stable within a day and rotates at midnight.
struct DailyQuote {
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
    static func forDate(_ date: Date) -> DailyQuote {
        guard !all.isEmpty else { return DailyQuote(text: "What did today teach you?", author: nil) }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return all[(day - 1) % all.count]
    }
}

// MARK: - Quick Action model

/// One deep-linked capture action rendered by both widget sizes.
private struct QuickAction: Identifiable {
    let title: String
    let systemImage: String
    let url: URL
    /// Two-stop gradient (top-leading → bottom-trailing) for the icon and label.
    let tint: [Color]

    var id: String { title }
    var accent: Color { tint.first ?? .accentColor }
}

private let quickActions: [QuickAction] = [
    QuickAction(title: "Write", systemImage: "pencil", url: URL(string: "reflect://write")!,
                tint: [Color(hex: "628141"), Color(hex: "40513B")]),
    QuickAction(title: "Photo", systemImage: "camera.fill", url: URL(string: "reflect://camera")!,
                tint: [Color(hex: "E67E22"), Color(hex: "D35400")]),
    QuickAction(title: "Voice", systemImage: "waveform", url: URL(string: "reflect://voice")!,
                tint: [Color(hex: "9B59B6"), Color(hex: "8E44AD")]),
    QuickAction(title: "Insight", systemImage: "lightbulb.fill", url: URL(string: "reflect://insight")!,
                tint: [Color(hex: "F5A623"), Color(hex: "E0821A")])
]

// MARK: - Provider

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        let now = Date()
        return QuickActionsEntry(date: now, quote: DailyQuote.forDate(now))
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> ()) {
        let now = Date()
        completion(QuickActionsEntry(date: now, quote: DailyQuote.forDate(now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let now = Date()
        let entry = QuickActionsEntry(date: now, quote: DailyQuote.forDate(now))
        // Refresh at the start of tomorrow so the daily quote turns over at midnight.
        let startOfTomorrow = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        )
        completion(Timeline(entries: [entry], policy: .after(startOfTomorrow)))
    }
}

// MARK: - Widget View

struct QuickActionsWidgetView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: QuickActionsEntry

    var body: some View {
        switch widgetFamily {
        case .systemMedium:
            mediumWidgetView
        default:
            smallWidgetView
        }
    }

    // MARK: Small — the four quick actions

    private var smallWidgetView: some View {
        VStack(spacing: 14) {
            writeButton(quickActions[0])

            HStack(spacing: 8) {
                ForEach(quickActions.dropFirst()) { action in
                    circleButton(action)
                }
            }
        }
    }

    // MARK: Medium — actions on the left, the day's quote on the right

    private var mediumWidgetView: some View {
        HStack(spacing: 16) {
            // Left: 2×2 grid of the four actions.
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    gridTile(quickActions[0])
                    gridTile(quickActions[1])
                }
                HStack(spacing: 10) {
                    gridTile(quickActions[2])
                    gridTile(quickActions[3])
                }
            }
            .frame(width: 128)

            Divider()

            // Right: daily quote.
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "628141").opacity(0.55))

                Text(entry.quote.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)

                if let author = entry.quote.author {
                    Text("— \(author)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Buttons

    /// Full-width labeled action (small widget's primary action).
    private func writeButton(_ action: QuickAction) -> some View {
        Link(destination: action.url) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(action.accent.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: action.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(colors: action.tint, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

                Text(action.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: action.tint, startPoint: .leading, endPoint: .trailing)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Capsule()
                    .fill(Color("WidgetCardSurface"))
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
            )
        }
    }

    /// Circular icon-only action (small widget's secondary row).
    private func circleButton(_ action: QuickAction) -> some View {
        Link(destination: action.url) {
            ZStack {
                Circle()
                    .fill(Color("WidgetCardSurface"))
                    .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)

                Image(systemName: action.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: action.tint, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
        }
    }

    /// Icon + label tile (medium widget's action grid).
    private func gridTile(_ action: QuickAction) -> some View {
        Link(destination: action.url) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(action.accent.opacity(0.14))

                    Image(systemName: action.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: action.tint, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                .frame(width: 40, height: 40)

                Text(action.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color("WidgetCardSurface"))
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
            )
        }
    }
}

// MARK: - Widget Configuration

struct Quick_Actions: Widget {
    let kind: String = "Quick_Actions"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            if #available(iOS 17.0, *) {
                QuickActionsWidgetView(entry: entry)
                    .containerBackground(for: .widget) { Color("WidgetBackground") }
            } else {
                QuickActionsWidgetView(entry: entry)
                    .padding()
                    .background(Color("WidgetBackground"))
            }
        }
        .configurationDisplayName("Reflect")
        .description("Quick access to write, capture photos, record voice reflections, or add insights — plus a daily reflection prompt.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Color Extension for Widget

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    Quick_Actions()
} timeline: {
    QuickActionsEntry(date: .now, quote: DailyQuote.forDate(.now))
}

#Preview(as: .systemMedium) {
    Quick_Actions()
} timeline: {
    QuickActionsEntry(date: .now, quote: DailyQuote.forDate(.now))
}
