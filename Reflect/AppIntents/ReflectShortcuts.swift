import AppIntents

/// The app's sole `AppShortcutsProvider`. Registers the quick-capture intents with Siri,
/// Shortcuts, and Spotlight so users can add an Insight or a Reflection by voice.
struct ReflectShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateInsightIntent(),
            phrases: [
                // Type-specific — lets the user say "Add a question / note".
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

        AppShortcut(
            intent: CreateReflectionIntent(),
            phrases: [
                "Add a reflection to \(.applicationName)",
                "Capture a reflection in \(.applicationName)",
                "New reflection in \(.applicationName)"
            ],
            shortTitle: "Add Reflection",
            systemImageName: "square.and.pencil"
        )
    }
}
