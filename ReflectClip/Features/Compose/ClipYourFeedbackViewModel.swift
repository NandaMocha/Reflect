import Foundation
import Observation
import os

/// Drives the Clip's "Your Feedback" composer (`ClipYourFeedbackView`): loads the request via the
/// public-DB mirror (AC-020), collects one draft per question, and on submit persists to the
/// offline-safe `PendingAnswerStore` (AC-021) before attempting the live POST
/// (`ClipFeedbackSubmitter`, AC-021/AC-015).
///
/// **Failure semantics (per AC-031's scope):** a draft is enqueued into `PendingAnswerStore`
/// *before* the network attempt, so a guest's text is never lost regardless of what the POST
/// does. A successful POST marks those entries `.sent` and advances `ClipSession` to
/// `.allFeedback`. A transient failure (`.network`/`.rateLimited`) keeps the guest on this screen
/// with the drafts intact and an honest "will send when online" banner plus a manual retry — the
/// entries stay `.queued` in the store either way, so the offline/foreground retry loop AC-021
/// documents still picks them up even if the guest never taps retry here. A `.linkRevoked`
/// failure is a dead link, not a transient one: it routes to `ClipSession`'s existing
/// `.invalidLink` phase rather than staying on a composer for a request that no longer exists.
@Observable
@MainActor
final class ClipYourFeedbackViewModel {

    // MARK: - State

    enum LoadState: Equatable {
        case loading
        case loaded
        case networkError(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var request: ClipRequest?
    private(set) var isSubmitting = false
    var submitErrorMessage: String?

    /// One draft per `SpaceQuestion.id`. Cleared only after a confirmed-sent submit — a failed
    /// attempt (of any kind) leaves this untouched so the guest never has to retype.
    var drafts: [String: String] = [:]

    // MARK: - Dependencies

    private let session: ClipSession
    private let repository: ClipSpaceRepositoring
    private let submitter: ClipFeedbackSubmitting
    private let pendingAnswerStore: PendingAnswerStoring
    private let logger = Logger(subsystem: "xyz.nandamochammad.Reflect.Clip", category: "ClipYourFeedbackViewModel")

    /// Matches `ANSWER_BODY_MAX_LENGTH` in `scripts/server/clip-feedback.php`, which is itself a
    /// hardcoded copy of this same constant (PHP can't import Swift) — see that file's comment.
    static let answerMaxLength = Constants.Limits.spaceResponseMaxLength

    // MARK: - Initialization

    init(
        session: ClipSession,
        repository: ClipSpaceRepositoring,
        submitter: ClipFeedbackSubmitting,
        pendingAnswerStore: PendingAnswerStoring
    ) {
        self.session = session
        self.repository = repository
        self.submitter = submitter
        self.pendingAnswerStore = pendingAnswerStore
    }

    // MARK: - Derived State

    var displayName: String {
        session.guestIdentity?.displayName ?? ""
    }

    var hasQuestions: Bool {
        !(request?.questions.isEmpty ?? true)
    }

    /// True once at least one draft is non-empty, none exceed `answerMaxLength`, and no submit
    /// is already in flight.
    var canSubmit: Bool {
        guard !isSubmitting else { return false }
        let entries = trimmedDraftEntries()
        guard !entries.isEmpty else { return false }
        return entries.allSatisfy { $0.body.count <= Self.answerMaxLength }
    }

    func draftLength(for questionId: String) -> Int {
        trimmed(drafts[questionId]).count
    }

    func isOverLimit(for questionId: String) -> Bool {
        draftLength(for: questionId) > Self.answerMaxLength
    }

    // MARK: - Actions

    func load() async {
        guard let token = session.requestToken else {
            session.markLinkInvalid()
            return
        }

        loadState = .loading
        do {
            let fetched = try await repository.fetchRequest(token: token)
            request = fetched
            loadState = .loaded
        } catch let error as ClipSpaceError {
            handleLoadFailure(error)
        } catch {
            loadState = .networkError(ClipSpaceError.network.localizedDescription)
        }
    }

    func retryLoad() async {
        await load()
    }

    /// Enqueues every non-empty, in-limit draft into `PendingAnswerStore` (never skipped — this
    /// is what makes the guest's text durable) and then attempts one batched POST. `SpaceQuestion`
    /// caps a request at 5 questions (`Constants.Limits.spaceMaxQuestions`), which already matches
    /// the endpoint's "≤ 5 answers per call" limit, so this never needs to split into multiple
    /// requests.
    func submit() async {
        guard canSubmit,
              let requestToken = session.requestToken,
              let identity = session.guestIdentity else {
            return
        }

        let entries = trimmedDraftEntries()
        guard !entries.isEmpty else { return }

        submitErrorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        var dtoAnswers: [ClipFeedbackAnswerDTO] = []
        dtoAnswers.reserveCapacity(entries.count)
        for entry in entries {
            let pending = await pendingAnswerStore.enqueue(questionId: entry.questionId, body: entry.body)
            dtoAnswers.append(
                ClipFeedbackAnswerDTO(questionId: entry.questionId, submissionId: pending.submissionId, body: entry.body)
            )
        }

        let submissionRequest = ClipFeedbackSubmissionRequest(
            requestToken: requestToken,
            guestId: identity.guestId.uuidString,
            guestName: identity.displayName,
            answers: dtoAnswers
        )

        do {
            let sentIds = try await submitter.submit(submissionRequest)
            await pendingAnswerStore.markSent(submissionIds: sentIds)
            for entry in entries {
                drafts.removeValue(forKey: entry.questionId)
            }
            session.advanceToAllFeedback()
        } catch ClipFeedbackError.linkRevoked {
            // The entries stay `.queued` in PendingAnswerStore per AC-021's watch-out — a
            // revoked link means the *endpoint* is closed, not that the guest's text should
            // vanish. There is nothing useful to retry against a dead link, though, so this
            // routes to ClipSession's existing "this link isn't working" phase rather than a
            // local retry banner.
            session.markLinkInvalid()
        } catch let error as ClipFeedbackError {
            logger.error("Submit failed — \(error.localizedDescription, privacy: .public)")
            submitErrorMessage = error.errorDescription
        } catch {
            logger.error("Submit failed with unexpected error — \(String(describing: error), privacy: .public)")
            submitErrorMessage = ClipFeedbackError.network.errorDescription
        }
    }

    func retrySubmit() async {
        await submit()
    }

    // MARK: - Private Helpers

    private func handleLoadFailure(_ error: ClipSpaceError) {
        switch error {
        case .invalidLink:
            session.markLinkInvalid()
        case .network, .iCloudUnavailable, .malformedData:
            loadState = .networkError(error.localizedDescription)
        }
    }

    private func trimmed(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every question's trimmed, non-empty draft, in the request's question order. Over-limit
    /// drafts are intentionally still included here (only `canSubmit`/the submit button gate on
    /// length) so a caller inspecting "what would be sent" sees the true set the guest typed.
    private func trimmedDraftEntries() -> [(questionId: String, body: String)] {
        guard let request else { return [] }
        return request.questions.compactMap { question in
            let text = trimmed(drafts[question.id])
            guard !text.isEmpty else { return nil }
            return (question.id, text)
        }
    }
}

// MARK: - DIContainer Factory

extension ClipDIContainer {
    func makeClipYourFeedbackViewModel(session: ClipSession) -> ClipYourFeedbackViewModel {
        ClipYourFeedbackViewModel(
            session: session,
            repository: makeClipSpaceRepository(),
            submitter: makeClipFeedbackSubmitter(),
            pendingAnswerStore: makePendingAnswerStore()
        )
    }
}
