import Foundation

protocol UpdateReflectionQuestionsUseCaseProtocol {
    func execute(_ reflection: SpaceReflection, in space: Space, title: String, note: String?, questions: [SpaceQuestion]) async throws -> SpaceReflection
}

/// Edit-your-own question rewrite (add/remove/reorder/reword). Validates the new question
/// set, then delegates to the repository, which hard-deletes answers to any removed question.
@MainActor
final class UpdateReflectionQuestionsUseCase: UpdateReflectionQuestionsUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(_ reflection: SpaceReflection, in space: Space, title: String, note: String?, questions: [SpaceQuestion]) async throws -> SpaceReflection {
        guard reflection.isMine else { throw SpaceError.notAuthor }
        try SpaceQuestion.validate(questions)

        return try await repository.updateReflectionQuestions(
            reflection,
            in: space,
            title: title,
            note: note,
            questions: questions
        )
    }
}
