import Foundation
import Observation

/// Backs the owner's post-creation edit of a reflection: title/note/question drafts seeded
/// from the reflection, plus the answers already posted against it so the UI can warn before
/// destructive or wording-changing edits (plan Phase 5).
@Observable
@MainActor
final class SpaceReflectionEditViewModel {

    // MARK: - State

    let space: Space
    let reflection: SpaceReflection

    var title: String
    var note: String
    var questions: [SpaceQuestion]
    var answers: [SpaceAnswer] = []

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let updateUseCase: UpdateReflectionQuestionsUseCaseProtocol
    private let fetchAnswersUseCase: FetchAnswersUseCaseProtocol

    // MARK: - Initialization

    init(
        space: Space,
        reflection: SpaceReflection,
        updateUseCase: UpdateReflectionQuestionsUseCaseProtocol,
        fetchAnswersUseCase: FetchAnswersUseCaseProtocol
    ) {
        self.space = space
        self.reflection = reflection
        self.title = reflection.title
        self.note = reflection.note ?? ""
        self.questions = reflection.questions
        self.updateUseCase = updateUseCase
        self.fetchAnswersUseCase = fetchAnswersUseCase
    }

    // MARK: - Computed

    /// Number of answers posted against a given question, regardless of author.
    func answerCount(for questionId: String) -> Int {
        answers.filter { $0.questionId == questionId }.count
    }

    /// IDs of questions still present in the draft whose wording changed since the original
    /// reflection, and that already have at least one answer — these need the reword warning.
    var editedQuestionIdsWithAnswers: Set<String> {
        let originalById = Dictionary(uniqueKeysWithValues: reflection.questions.map { ($0.id, $0.text) })
        var result: Set<String> = []
        for question in questions {
            guard let originalText = originalById[question.id], originalText != question.text else { continue }
            guard answerCount(for: question.id) >= 1 else { continue }
            result.insert(question.id)
        }
        return result
    }

    /// IDs of original questions removed from the draft that already have at least one
    /// answer — deleting them will hard-delete those answers.
    var removedQuestionIdsWithAnswers: Set<String> {
        let remainingIds = Set(questions.map(\.id))
        var result: Set<String> = []
        for question in reflection.questions where !remainingIds.contains(question.id) {
            guard answerCount(for: question.id) >= 1 else { continue }
            result.insert(question.id)
        }
        return result
    }

    // MARK: - Actions

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            answers = try await fetchAnswersUseCase.execute(for: reflection, in: space)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persists the edited title/note/questions and returns the updated reflection.
    @discardableResult
    func save() async throws -> SpaceReflection {
        isSaving = true
        defer { isSaving = false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await updateUseCase.execute(
            reflection,
            in: space,
            title: trimmedTitle,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            questions: questions
        )
    }
}
