import AppIntents
import SwiftData

/// Quick-captures an `Insight` from Siri, Shortcuts, or Spotlight without foregrounding
/// the app. Writes go straight to the shared App-Group store so the save is durable even
/// when the run is backgrounded.
struct CreateInsightIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Insight"
    static let description = IntentDescription("Quickly capture a question, note, or reflection to review later.")
    static let openAppWhenRun = false

    @Parameter(title: "Insight", requestValueDialog: "What's on your mind?")
    var text: String

    @Parameter(title: "Type", default: .note)
    var type: InsightType

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $text.needsValueError("What's on your mind?")
        }
        let context = InsightStore.container.mainContext
        context.insert(Insight(text: trimmed, type: type))
        try context.save()
        return .result(dialog: "Saved your \(type.title.lowercased()) to Reflect.")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$type) \u{201C}\(\.$text)\u{201D} to Reflect")
    }
}
