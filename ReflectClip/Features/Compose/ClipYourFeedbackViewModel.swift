import Foundation
import Observation
import UIKit
import os

/// Drives the Clip's "Your Feedback" composer (`ClipYourFeedbackView`): loads the request via the
/// public-DB mirror (AC-020), collects one draft per question, and on submit persists to the
/// offline-safe `PendingAnswerStore` (AC-021) before attempting the live POST
/// (`ClipFeedbackSubmitter`, AC-021/AC-015).
///
/// **Failure semantics (per AC-031's scope):** a draft is enqueued into `PendingAnswerStore`
/// *before* the network attempt (reusing the same entry/`submissionId` on every retry — see
/// `submit()`), so a guest's text is never lost regardless of what the POST does. A successful
/// POST marks those entries `.sent` and advances `ClipSession` to `.allFeedback`. A transient
/// failure (`.network`/`.rateLimited`) keeps the guest on this screen with the drafts intact and
/// an honest "will send when online" banner plus a manual retry — the entries stay `.queued` in
/// the store either way, so the offline/foreground retry loop AC-021 documents still picks them
/// up even if the guest never taps retry here. A `.linkRevoked` failure is a dead link, not a
/// transient one: the affected entries are marked `.failed` (so they stop being retried against a
/// dead endpoint) and it routes to `ClipSession`'s existing `.invalidLink` phase rather than
/// staying on a composer for a request that no longer exists.
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
    /// Decoded once when `request` loads, rather than in the view body — `UIImage(data:)` is a
    /// non-trivial main-thread decode and the view body re-evaluates on every keystroke.
    private(set) var thumbnailImage: UIImage?
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
        return entries.allSatisfy { $0.body.unicodeScalars.count <= Self.answerMaxLength }
    }

    /// Counts Unicode scalars (code points), matching PHP's `mb_strlen` on the server
    /// (`scripts/server/clip-feedback.php`), not Swift's grapheme-cluster `String.count`. A body
    /// with emoji or combining marks can have fewer grapheme clusters than code points, so
    /// grapheme counting here could pass client-side validation while the server's `mb_strlen`
    /// check (which counts code points) still rejects it with a deterministic 400 — collapsed by
    /// `ClipFeedbackSubmitter` into a generic `.network` error that retries forever against a
    /// rejection that will never succeed. Counting the same unit as the server keeps the two
    /// checks in agreement.
    func draftLength(for questionId: String) -> Int {
        trimmed(drafts[questionId]).unicodeScalars.count
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
            thumbnailImage = fetched.thumbnailData.flatMap { UIImage(data: $0) }
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

    /// Ensures every non-empty, in-limit draft has exactly one `.queued` `PendingAnswerStore`
    /// entry (reusing an existing entry's `submissionId` — and amending its body if the guest
    /// edited the draft since the last attempt — rather than minting a new one on every call),
    /// then attempts one batched POST. Reusing the same `submissionId` across retries is the
    /// idempotency contract AC-021 documents: `LivePendingAnswerStore.enqueue` mints a fresh UUID
    /// on every call, so calling it unconditionally on a retry (or a normal re-tap of Send after a
    /// failure) would leave the earlier queued entry orphaned — never marked `.sent`, but still
    /// picked up and POSTed by AC-021's background retry loop, double-ingesting the answer.
    /// `SpaceQuestion` caps a request at 5 questions (`Constants.Limits.spaceMaxQuestions`), which
    /// already matches the endpoint's "≤ 5 answers per call" limit, so this never needs to split
    /// into multiple requests.
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

        // Reuse any already-queued entry for a question instead of re-enqueuing — this is the
        // fix for the duplicate-enqueue bug: only questions with no `.queued` entry yet mint a
        // new `submissionId`. `enqueueIfAbsent` makes the "reuse or create" decision atomically
        // inside `pendingAnswerStore`'s actor isolation, so there's no check-then-act window
        // between snapshotting existing entries and acting on them — see that method's doc
        // comment for why that matters even though `submit()` is reentrancy-guarded today.
        var dtoAnswers: [ClipFeedbackAnswerDTO] = []
        dtoAnswers.reserveCapacity(entries.count)
        for entry in entries {
            let pending = await pendingAnswerStore.enqueueIfAbsent(questionId: entry.questionId, body: entry.body)
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
            // The entries stay in PendingAnswerStore per AC-021's watch-out — a revoked link
            // means the *endpoint* is closed, not that the guest's text should vanish. But
            // there's nothing useful to retry against a dead link, so mark exactly the entries
            // from this attempt `.failed`: they stop being picked up by AC-021's retry loop
            // (which reads `.queued` only) instead of being POSTed against a 404 forever, and a
            // future UI (AC-032) can render them honestly rather than "Sending…" indefinitely.
            await pendingAnswerStore.markFailed(submissionIds: dtoAnswers.map(\.submissionId))
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
