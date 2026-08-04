import Foundation
import Observation
import UIKit

/// Backs one reflection's answering flow: per-question answers, posting, and deleting your
/// own. Cache-first paint, sync-on-appear; not real-time — designed for "recently synced"
/// (plan §11.4). One answer per member per question (upsert replaces, never duplicates).
@Observable
@MainActor
final class SpaceThreadViewModel {

    // MARK: - State

    let space: Space
    let reflection: SpaceReflection
    var answers: [SpaceAnswer] = []
    /// The question currently shown in the composer. Defaults to the first question I haven't
    /// answered yet so members are steered toward finishing the set.
    var activeQuestionId: String?
    var isRefreshing: Bool = false
    var errorMessage: String?

    var draft: String = ""
    var draftImage: UIImage?
    var isPosting: Bool = false

    // MARK: - Dependencies

    private let fetchUseCase: FetchAnswersUseCaseProtocol
    private let upsertUseCase: UpsertAnswerUseCaseProtocol
    private let deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol
    private let repository: SpaceRepositoryProtocol

    // MARK: - Initialization

    init(
        space: Space,
        reflection: SpaceReflection,
        fetchUseCase: FetchAnswersUseCaseProtocol,
        upsertUseCase: UpsertAnswerUseCaseProtocol,
        deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.space = space
        self.reflection = reflection
        self.fetchUseCase = fetchUseCase
        self.upsertUseCase = upsertUseCase
        self.deleteUseCase = deleteUseCase
        self.repository = repository
    }

    // MARK: - Computed

    var responseLimit: Int { Constants.Limits.spaceResponseMaxLength }
    var draftCount: Int { draft.count }

    /// My answer to a given question, if I've posted one.
    func myAnswer(for questionId: String?) -> SpaceAnswer? {
        guard let questionId else { return nil }
        return answers.first { $0.isMine && $0.questionId == questionId }
    }

    /// IDs of the questions I've already answered.
    var answeredQuestionIds: Set<String> {
        Set(answers.filter(\.isMine).map(\.questionId))
    }

    /// All answers (any author) to a given question.
    func answers(for questionId: String) -> [SpaceAnswer] {
        answers.filter { $0.questionId == questionId }
    }

    var activeQuestion: SpaceQuestion? {
        guard let activeQuestionId else { return nil }
        return reflection.questions.first { $0.id == activeQuestionId }
    }

    /// True when submitting the composer would overwrite an answer I already posted, rather
    /// than create a new one.
    var isEditingExistingAnswer: Bool {
        myAnswer(for: activeQuestionId) != nil
    }

    var canPost: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return activeQuestionId != nil && !trimmed.isEmpty && trimmed.count <= responseLimit && !isPosting
    }

    // MARK: - Actions

    func load() async {
        answers = repository.cachedAnswers(reflectionID: reflection.id)
        if activeQuestionId == nil {
            activeQuestionId = firstUnansweredQuestionId()
        }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            answers = try await fetchUseCase.execute(for: reflection, in: space)
            if activeQuestionId == nil {
                activeQuestionId = firstUnansweredQuestionId()
            }
            errorMessage = nil
        } catch is CancellationError {
            // Cancelled pull-to-refresh — not a real error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears whatever the composer is currently showing (edit prefill or a fresh draft),
    /// leaving `activeQuestionId` untouched so the composer stays pointed at the same question.
    func clearDraftPrefill() {
        draft = ""
        draftImage = nil
    }

    /// Makes a question active, prefilling the composer from my existing answer when present.
    func select(questionId: String) {
        activeQuestionId = questionId
        if let existing = myAnswer(for: questionId) {
            draft = existing.text
            draftImage = existing.imageData.flatMap(UIImage.init(data:))
        } else {
            draft = ""
            draftImage = nil
        }
    }

    /// Posts the draft to the active question and auto-advances to the next unanswered one.
    func submit() async {
        guard canPost, let questionId = activeQuestionId else { return }
        isPosting = true
        defer { isPosting = false }
        // Land our display name in the zone before the answer, so other members see who
        // answered instead of "A member".
        await registerMyDisplayNameIfKnown()
        do {
            let answer = try await upsertUseCase.execute(
                to: reflection,
                in: space,
                questionId: questionId,
                text: draft,
                image: draftImage
            )
            if let index = answers.firstIndex(where: { $0.id == answer.id }) {
                answers[index] = answer
            } else {
                answers.append(answer)
            }
            draft = ""
            draftImage = nil
            HapticManager.shared.success()
            if let next = firstUnansweredQuestionId() {
                select(questionId: next)
            } else {
                activeQuestionId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    func deleteOwnAnswer(for questionId: String) async {
        guard let answer = myAnswer(for: questionId) else { return }
        do {
            try await deleteUseCase.execute(answer: answer, in: space)
            answers.removeAll { $0.id == answer.id }
            if activeQuestionId == questionId {
                draft = ""
                draftImage = nil
            }
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    // MARK: - Private Helpers

    private func firstUnansweredQuestionId() -> String? {
        let answered = answeredQuestionIds
        return reflection.questions.first { !answered.contains($0.id) }?.id
    }

    /// Best-effort mirror of the saved display name into the space's zone. Silent — a failed
    /// registration must never block posting.
    private func registerMyDisplayNameIfKnown() async {
        guard let name = UserDefaults.standard.spaceDisplayName() else { return }
        try? await repository.registerDisplayName(name, in: space)
    }
}
