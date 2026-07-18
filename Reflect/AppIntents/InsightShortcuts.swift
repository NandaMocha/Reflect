import AppIntents

/// The app's sole `AppShortcutsProvider`. Registers `CreateInsightIntent` with Siri and
/// Shortcuts so users can quick-capture an Insight by voice or from Spotlight.
struct InsightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateInsightIntent(),
            phrases: [
                // Type-specific — lets the user say "Add a question / note / reflection".
                "Add a \(\.$type) to \(.applicationName)",
                "Capture a \(\.$type) in \(.applicationName)",
                "New \(\.$type) in \(.applicationName)",
                // Generic — the app then asks which type.
                "Add an insight to \(.applicationName)",
                "Capture an insight in \(.applicationName)"
            ],
            shortTitle: "Add Insight",
            systemImageName: "lightbulb.fill"
        )
    }
}
