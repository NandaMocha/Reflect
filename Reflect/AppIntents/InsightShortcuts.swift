import AppIntents

/// The app's sole `AppShortcutsProvider`. Registers `CreateInsightIntent` with Siri and
/// Shortcuts so users can quick-capture an Insight by voice or from Spotlight.
struct InsightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateInsightIntent(),
            phrases: [
                "Add an insight to \(.applicationName)",
                "Capture an insight in \(.applicationName)",
                "New insight in \(.applicationName)"
            ],
            shortTitle: "Add Insight",
            systemImageName: "lightbulb.fill"
        )
    }
}
