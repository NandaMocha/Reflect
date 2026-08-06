import Foundation
import Observation
import os

/// One row in the "All feedback" list: either a mirror-confirmed answer, or this guest's own
/// answer that hasn't shown up in the mirror yet, rendered from the local `PendingAnswerStore`
/// (AC-021) as an optimistic echo.
enum ClipFeedbackItem: Identifiable {
    case confirmed(SpaceAnswer)
    case pending(PendingAnswer)

    var id: String {
        switch self {
        case .confirmed(let answer): return "confirmed-\(answer.id)"
        case .pending(let answer): return "pending-\(answer.submissionId)"
        }
    }

    var questionId: String {
        switch self {
        case .confirmed(let answer): return answer.questionId
        case .pending(let answer): return answer.questionId
        }
    }
}

/// Drives the Clip's "All feedback" screen (`ClipAllFeedbackView`): everyone's answers, grouped by
/// question, with this guest's own not-yet-confirmed answers merged in as pending bubbles.
///
/// **Merge/dedup contract (per AC-032's watch-out):** the dedup key between a `PendingAnswerStore`
/// entry and a `MirroredAnswer` is `guestId`+`questionId` — **not** a text match, since a guest's
/// local draft text and the eventually-mirrored text are not guaranteed byte-identical (trimming,
/// re-encoding). `PendingAnswerStore.enqueueIfAbsent` already guarantees at most one `.queued`
/// entry per `questionId` for this guest, so "does a confirmed answer exist for this guest on this
/// question" is sufficient to know the pending entry is now redundant — no count/text matching is
/// needed beyond that. Once the mirror fetch reports a confirmed answer for
/// (`ownGuestId`, `questionId`), `PendingAnswerStore.dropConfirmedAnswers` removes the now-redundant
/// `.sent` entry, and any leftover pending entry for that same question (an edge case — e.g. a
/// `.failed` entry orphaned by a previous launch) is filtered out of the merged list here too, so a
/// confirmed answer can never render twice.
@Observable
@MainActor
final class ClipAllFeedbackViewModel {

    // MARK: - State

    enum LoadState: Equatable {
        case loading
        case loaded
        case networkError(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var request: ClipRequest?
    private(set) var confirmedAnswers: [SpaceAnswer] = []
    private(set) var pendingItems: [PendingAnswer] = []
    /// Set only by a failed pull-to-refresh *after* content has already loaded once — a refresh
    /// failure shouldn't blank out a list the guest can already see, so this surfaces as a
    /// transient banner instead of flipping `loadState` back to `.networkError`.
    var refreshErrorMessage: String?

    // MARK: - Dependencies

    private let session: ClipSession
    private let repository: ClipSpaceRepositoring
    private let pendingAnswerStore: PendingAnswerStoring
    private let installContinuityStore: ClipInstallContinuityStoring
    private let logger = Logger(subsystem: "xyz.nandamochammad.Reflect.Clip", category: "ClipAllFeedbackViewModel")

    /// Guards against `load()` (from `.task`) and `refresh()` (from `.refreshable`) running
    /// concurrently — without this, two overlapping `fetch(isInitialLoad:)` calls could each
    /// reset/overwrite state independently and whichever response lands last wins regardless of
    /// which one started first.
    private var isFetching = false

    // MARK: - Initialization

    init(
        session: ClipSession,
        repository: ClipSpaceRepositoring,
        pendingAnswerStore: PendingAnswerStoring,
        installContinuityStore: ClipInstallContinuityStoring
    ) {
        self.session = session
        self.repository = repository
        self.pendingAnswerStore = pendingAnswerStore
        self.installContinuityStore = installContinuityStore
    }

    // MARK: - Derived State

    var questions: [SpaceQuestion] {
        request?.questions ?? []
    }

    var hasAnyFeedback: Bool {
        !confirmedAnswers.isEmpty || !pendingItems.isEmpty
    }

    /// Confirmed answers (already ordered question-then-`answerIndex` by the repository) followed
    /// by this guest's still-pending answers for the same question — appended last since they're
    /// always the most recent thing this guest did.
    func items(for questionId: String) -> [ClipFeedbackItem] {
        var items = confirmedAnswers
            .filter { $0.questionId == questionId }
            .map(ClipFeedbackItem.confirmed)
        items.append(contentsOf: pendingItems
            .filter { $0.questionId == questionId }
            .map(ClipFeedbackItem.pending))
        return items
    }

    // MARK: - Actions

    /// First load — used by the view's `.task`. Shows a full-screen spinner/error since there's
    /// no prior content to preserve.
    func load() async {
        loadState = .loading
        await fetch(isInitialLoad: true)
    }

    /// Pull-to-refresh — used by `.refreshable`. Keeps whatever is already on screen and only
    /// surfaces a failure as a dismissable banner via `refreshErrorMessage`.
    func refresh() async {
        refreshErrorMessage = nil
        await fetch(isInitialLoad: loadState != .loaded)
    }

    /// AC-040: whether `ClipAllFeedbackView.onAppear` should present the `SKOverlay` install
    /// upsell right now. True at most once ever (per App Group lifetime, via
    /// `installContinuityStore`'s persisted flag) and only once this guest has actually reached
    /// `.sent` on at least one answer — "after the first successful submit," not merely after
    /// landing on this screen. Marks the flag before returning `true` so a caller can't
    /// accidentally re-present by calling this twice in the same session; the underlying flag
    /// also makes the check itself idempotent across relaunches.
    ///
    /// Presenting the overlay itself needs a `UIWindowScene`, which this `@MainActor` view model
    /// deliberately doesn't reach for — that stays in `ClipAllFeedbackView`, the same
    /// view/view-model split every other Clip screen uses.
    func presentInstallOverlayIfNeeded() async -> Bool {
        guard !installContinuityStore.hasShownInstallOverlay() else { return false }
        let hasReachedSent = await pendingAnswerStore.allAnswers().contains { $0.state == .sent }
        guard hasReachedSent else { return false }
        installContinuityStore.markInstallOverlayShown()
        return true
    }

    // MARK: - Private Helpers

    private func fetch(isInitialLoad: Bool) async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let token = session.requestToken, let identity = session.guestIdentity else {
            session.markLinkInvalid()
            return
        }

        // AC-040: this screen is only reached after a resolved request the guest actually
        // engaged with — record it so the full app can recognize a Clip-driven install on its
        // own first cold launch (`SpaceInviteInbox.consumeClipDrivenInstall()`).
        installContinuityStore.recordLastRequestToken(token)

        do {
            async let requestTask = repository.fetchRequest(token: token)
            async let answersTask = repository.fetchAnswers(token: token, ownGuestId: identity.guestId.uuidString)
            let (fetchedRequest, fetchedAnswers) = try await (requestTask, answersTask)

            request = fetchedRequest
            confirmedAnswers = fetchedAnswers

            // Only questions where a mirrored answer with *our* guestId showed up count as
            // confirmed for the merge — a question with other guests'/members' answers but none
            // of ours yet must keep showing our pending bubble.
            let confirmedQuestionIds = Set(
                fetchedAnswers.filter { $0.guestId == identity.guestId.uuidString }.map(\.questionId)
            )
            await pendingAnswerStore.dropConfirmedAnswers(confirmedQuestionIds: confirmedQuestionIds)
            pendingItems = await pendingAnswerStore.allAnswers()
                .filter { !confirmedQuestionIds.contains($0.questionId) }

            loadState = .loaded
        } catch let error as ClipSpaceError {
            handleFetchFailure(error, isInitialLoad: isInitialLoad)
        } catch {
            handleFetchFailure(.network, isInitialLoad: isInitialLoad)
        }
    }

    private func handleFetchFailure(_ error: ClipSpaceError, isInitialLoad: Bool) {
        switch error {
        case .invalidLink:
            // A dead link is a dead link regardless of whether this was the first load or a
            // pull-to-refresh — always route off this screen rather than leaving the guest on a
            // list for a request that no longer exists.
            session.markLinkInvalid()
        case .network, .iCloudUnavailable, .malformedData:
            if isInitialLoad {
                loadState = .networkError(error.localizedDescription)
            } else {
                logger.error("Refresh failed — \(error.localizedDescription, privacy: .public)")
                refreshErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - DIContainer Factory

extension ClipDIContainer {
    func makeClipAllFeedbackViewModel(session: ClipSession) -> ClipAllFeedbackViewModel {
        ClipAllFeedbackViewModel(
            session: session,
            repository: makeClipSpaceRepository(),
            pendingAnswerStore: makePendingAnswerStore(),
            installContinuityStore: makeClipInstallContinuityStore()
        )
    }
}
