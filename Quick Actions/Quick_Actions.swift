//
//  Quick_Actions.swift
//  Quick Actions
//
//  Reflect Widget - Quick access to create reflections
//

import WidgetKit
import SwiftUI

// MARK: - Widget Entry

extension QuickActionsEntry: TimelineEntry {}

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
    QuickAction(title: "Write", systemImage: "pencil", url: WidgetDeepLink.write.url,
                tint: [Color(hex: "628141"), Color(hex: "40513B")]),
    QuickAction(title: "Photo", systemImage: "camera.fill", url: WidgetDeepLink.camera.url,
                tint: [Color(hex: "E67E22"), Color(hex: "D35400")]),
    QuickAction(title: "Voice", systemImage: "waveform", url: WidgetDeepLink.voice.url,
                tint: [Color(hex: "9B59B6"), Color(hex: "8E44AD")]),
    QuickAction(title: "Insight", systemImage: "lightbulb.fill", url: WidgetDeepLink.insight.url,
                tint: [Color(hex: "F5A623"), Color(hex: "E0821A")])
]

// MARK: - Provider

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsTimeline.entry(for: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> ()) {
        completion(QuickActionsTimeline.entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let now = Date()
        let entry = QuickActionsTimeline.entry(for: now)
        // Refresh at the start of tomorrow so the daily quote turns over at midnight.
        completion(Timeline(entries: [entry], policy: .after(QuickActionsTimeline.nextRefreshDate(after: now))))
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
