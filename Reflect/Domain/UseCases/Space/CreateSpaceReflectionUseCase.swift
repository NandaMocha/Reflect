import Foundation

protocol CreateSpaceReflectionUseCaseProtocol {
    func execute(in space: Space, title: String, promptText: String) async throws -> SpaceReflection
}

/// Validates a reflection's title (1...max) and prompt (non-empty) before creating it.
@MainActor
final class CreateSpaceReflectionUseCase: CreateSpaceReflectionUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(in space: Space, title: String, promptText: String) async throws -> SpaceReflection {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw SpaceError.titleRequired }
        guard trimmedTitle.count <= Constants.Limits.spaceReflectionTitleMaxLength else { throw SpaceError.titleTooLong }

        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { throw SpaceError.promptRequired }
        guard trimmedPrompt.count <= Constants.Limits.spaceReflectionPromptMaxLength else { throw SpaceError.promptTooLong }

        return try await repository.createReflection(in: space, title: trimmedTitle, promptText: trimmedPrompt)
    }
}
