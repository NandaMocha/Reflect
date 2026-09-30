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
        // Refresh at the next tone slot (05:00, 12:00, 18:00) so the quote matches the time of day.
        completion(Timeline(entries: [entry], policy: .after(QuickActionsTimeline.nextRefreshDate(after: now))))
    }
}

// MARK: - Widget Configuration

struct Quick_Actions: Widget {
    let kind: String = "Quick_Actions"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            // Views live in Shared/Widget/QuickActionsWidgetView.swift so the app's tests can render them.
            QuickActionsWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
        }
        .configurationDisplayName("Reflect")
        .description("Quick access to write, capture photos, record voice reflections, or add insights — plus a daily reflection prompt.")
        .supportedFamilies([.systemSmall, .systemMedium])
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
