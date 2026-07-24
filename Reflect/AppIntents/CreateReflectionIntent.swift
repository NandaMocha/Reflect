import AppIntents
import Foundation

/// Quick-captures a `Reflection` into the user's default Learning (last used, else the
/// first available) from Siri, Shortcuts, or Spotlight — no Learning picker. Routes
/// through `CreateReflectionUseCase`, the same path as the in-app editor.
struct CreateReflectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Reflection"
    static let description = IntentDescription("Quickly capture a reflection in your default learning.")
    static let openAppWhenRun = false

    @Parameter(title: "Reflection", requestValueDialog: "What did you learn or reflect on?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $text.needsValueError("What did you learn or reflect on?")
        }

        // Resolve the default Learning: last used, else the first available.
        let learnings = try await DIContainer.shared.makeFetchLearningsUseCase().execute()
        guard !learnings.isEmpty else {
            throw ReflectionIntentError.noLearning
        }
        let learning = UserDefaults.standard.lastUsedLearningId()
            .flatMap { id in learnings.first { $0.id == id } }
            ?? learnings[0]

        // Derive a title from the first line; the full text is the content.
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let title = String(firstLine.prefix(80))

        let input = CreateReflectionInput(
            title: title,
            content: trimmed,
            learningId: learning.id
        )
        _ = try await DIContainer.shared.makeCreateReflectionUseCase().execute(input: input)

        return .result(dialog: "Saved your reflection to \(learning.title).")
    }
}

enum ReflectionIntentError: Error, LocalizedError {
    case noLearning

    var errorDescription: String? {
        switch self {
        case .noLearning:
            return "Create a Learning in Reflect first, then try again."
        }
    }
}
