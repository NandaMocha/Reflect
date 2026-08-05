import Foundation
import Observation
import UIKit

/// Backs one reflection's answering flow: per-question answers, posting, and deleting your
/// own. Cache-first paint, sync-on-appear; not real-time — designed for "recently synced"
/// (plan §11.4). Members may post multiple answers per question; editing targets a specific
/// answer id rather than a question.
@Observable
@MainActor
final class SpaceThreadViewModel {

    // MARK: - State

    let space: Space
    var reflection: SpaceReflection
    var answers: [SpaceAnswer] = []
    /// The question currently shown in the segmented control / composer. Always has a value —
    /// there is no "nothing selected" state.
    var selectedQuestionId: String
    /// The answer id being edited, if any. `nil` means the composer will create a new answer.
    var editingAnswerID: String?
    var isRefreshing: Bool = false
    var errorMessage: String?

    var draft: String = ""
    var draftImage: UIImage?
    var isPosting: Bool = false
    /// Set after a successful export; the view watches this to present the share sheet.
    var exportedFileURL: URL?

    // MARK: - Dependencies

    private let fetchUseCase: FetchAnswersUseCaseProtocol
    private let writeUseCase: AnswerWriteUseCaseProtocol
    private let deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol
    private let repository: SpaceRepositoryProtocol
    private let exportUseCase: ExportFeedbackRequestUseCaseProtocol

    // MARK: - Initialization

    init(
        space: Space,
        reflection: SpaceReflection,
        fetchUseCase: FetchAnswersUseCaseProtocol,
        writeUseCase: AnswerWriteUseCaseProtocol,
        deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol,
        repository: SpaceRepositoryProtocol,
        exportUseCase: ExportFeedbackRequestUseCaseProtocol
    ) {
        self.space = space
        self.reflection = reflection
        self.selectedQuestionId = reflection.questions.first?.id ?? ""
        self.fetchUseCase = fetchUseCase
        self.writeUseCase = writeUseCase
        self.deleteUseCase = deleteUseCase
        self.repository = repository
        self.exportUseCase = exportUseCase
    }

    // MARK: - Computed

    var responseLimit: Int { Constants.Limits.spaceResponseMaxLength }
    var draftCount: Int { draft.count }

    /// My answers to a given question, oldest first.
    func myAnswers(for questionId: String) -> [SpaceAnswer] {
        answers
            .filter { $0.isMine && $0.questionId == questionId }
            .sorted { ($0.modifiedAt ?? $0.createdAt ?? .distantPast) < ($1.modifiedAt ?? $1.createdAt ?? .distantPast) }
    }

    /// The number of answers I've posted to a given question, for the segment dot.
    func myAnswerCount(for questionId: String) -> Int {
        myAnswers(for: questionId).count
    }

    /// All answers (any author) to a given question, oldest first.
    func answers(for questionId: String) -> [SpaceAnswer] {
        answers
            .filter { $0.questionId == questionId }
            .sorted { ($0.modifiedAt ?? $0.createdAt ?? .distantPast) < ($1.modifiedAt ?? $1.createdAt ?? .distantPast) }
    }

    var selectedQuestion: SpaceQuestion? {
        reflection.questions.first { $0.id == selectedQuestionId }
    }

    var canPost: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= responseLimit && !isPosting
    }

    // MARK: - Actions

    func load() async {
        answers = repository.cachedAnswers(reflectionID: reflection.id)
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            answers = try await fetchUseCase.execute(for: reflection, in: space)
            errorMessage = nil
        } catch is CancellationError {
            // Cancelled pull-to-refresh — not a real error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Changes which question's answers are shown. Does not touch the composer.
    func select(questionId: String) {
        selectedQuestionId = questionId
    }

    /// Points the composer at an existing answer for editing.
    func beginEditing(_ answer: SpaceAnswer) {
        editingAnswerID = answer.id
        selectedQuestionId = answer.questionId
        draft = answer.text
        draftImage = answer.imageData.flatMap(UIImage.init(data:))
    }

    /// Abandons an in-progress edit, clearing the composer back to a fresh draft.
    func cancelEditing() {
        editingAnswerID = nil
        draft = ""
        draftImage = nil
    }

    /// Posts the draft — creating a new answer, or updating the one being edited.
    func submit() async {
        guard canPost else { return }
        isPosting = true
        defer { isPosting = false }
        // Land our display name in the zone before the answer, so other members see who
        // answered instead of "A member".
        await registerMyDisplayNameIfKnown()
        do {
            let answer: SpaceAnswer
            if let editingAnswerID, let existing = answers.first(where: { $0.id == editingAnswerID }) {
                answer = try await writeUseCase.update(answer: existing, in: space, text: draft, image: draftImage)
            } else {
                answer = try await writeUseCase.create(
                    to: reflection,
                    in: space,
                    questionId: selectedQuestionId,
                    text: draft,
                    image: draftImage
                )
            }
            if let index = answers.firstIndex(where: { $0.id == answer.id }) {
                answers[index] = answer
            } else {
                answers.append(answer)
            }
            draft = ""
            draftImage = nil
            editingAnswerID = nil
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    /// Adopts an edited reflection (new title/note/questions) and refreshes answers, since a
    /// question rewording or removal cascade may have deleted some of them server-side.
    func applyEditedReflection(_ updated: SpaceReflection) async {
        reflection = updated
        if !updated.questions.contains(where: { $0.id == selectedQuestionId }) {
            selectedQuestionId = updated.questions.first?.id ?? ""
        }
        await refresh()
    }

    func deleteOwnAnswer(_ answer: SpaceAnswer) async {
        do {
            try await deleteUseCase.execute(answer: answer, in: space)
            answers.removeAll { $0.id == answer.id }
            if editingAnswerID == answer.id {
                editingAnswerID = nil
                draft = ""
                draftImage = nil
            }
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    /// Exports every question's answers (not just the currently filtered one) to a file and
    /// stages it for sharing via `exportedFileURL`.
    func export(format: FeedbackExportFormat) async {
        do {
            let url = try await exportUseCase.execute(
                input: ExportFeedbackRequestUseCase.Input(reflection: reflection, answers: answers, format: format)
            )
            exportedFileURL = url
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    // MARK: - Private Helpers

    /// Best-effort mirror of the saved display name into the space's zone. Silent — a failed
    /// registration must never block posting.
    private func registerMyDisplayNameIfKnown() async {
        guard let name = UserDefaults.standard.spaceDisplayName() else { return }
        try? await repository.registerDisplayName(name, in: space)
    }
}
