import AppIntents

/// Quick-captures an `Insight` from Siri, Shortcuts, or Spotlight without foregrounding
/// the app. Routes through `CreateInsightUseCase` (same path as the in-app editor) so
/// validation — e.g. the 500-character limit — is enforced for Siri dictation too.
struct CreateInsightIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Insight"
    static let description = IntentDescription("Quickly capture a question, note, or reflection to review later.")
    static let openAppWhenRun = false

    @Parameter(title: "Type", requestValueDialog: "Is it a question, a note, or a reflection?")
    var type: InsightType

    @Parameter(title: "Insight", requestValueDialog: "What's on your mind?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $text.needsValueError("What's on your mind?")
        }
        do {
            _ = try await DIContainer.shared.makeCreateInsightUseCase().execute(text: trimmed, type: type)
        } catch let error as InsightError {
            throw error
        }
        return .result(dialog: "Saved your \(type.title.lowercased()) to Reflect.")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$type) \u{201C}\(\.$text)\u{201D} to Reflect")
    }
}
