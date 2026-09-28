import Foundation
import os

// MARK: - Domain Model

/// One guest answer that has been (or is about to be) submitted, kept locally so it can be
/// retried on failure and echoed optimistically before a `MirroredAnswer` confirms it landed —
/// the "optimistic echo" mitigation `app-clip-plan.md` calls load-bearing, owned by AC-031/032.
/// `nonisolated`: a pure value type with no shared mutable state, constructed both from
/// `LivePendingAnswerStore`'s actor-isolated context and (later, by AC-031/032) from
/// `@MainActor` ViewModels. Without this, the Clip's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// setting would implicitly pin the initializer to the main actor, making it impossible to call
/// synchronously from `LivePendingAnswerStore`'s own (non-main) actor isolation domain — the same
/// class of issue `ClipMirrorSchema.swift` documents for its own types.
nonisolated struct PendingAnswer: Codable, Equatable, Sendable, Identifiable {
    /// State machine for one answer's journey from composer to confirmed mirror record.
    /// Modeled as an enum (not booleans) per AC-031's watch-out: "queued vs sent vs confirmed" is
    /// design-critical, and separate `isSent`/`isConfirmed` bools can represent nonsense states.
    /// "Confirmed" itself isn't stored here — a `.sent` entry simply stops existing once
    /// `dropConfirmedAnswers` removes it, so the store only ever holds `.queued`/`.sent`/`.failed`.
    enum State: String, Codable, Sendable {
        /// Enqueued locally; either never POSTed yet or every POST attempt so far has failed with
        /// a transient error. Still eligible for retry.
        case queued
        /// The write endpoint (AC-015) confirmed this `submissionId` was written. Kept around
        /// (rather than deleted immediately) so the optimistic echo still renders it until a
        /// `MirroredAnswer` shows up — deleting on `.sent` would reopen the exact gap the
        /// mitigation exists to close.
        case sent
        /// The write endpoint deterministically rejected this `submissionId`'s link as revoked or
        /// expired (`ClipFeedbackError.linkRevoked`, HTTP 404/410) — retrying is pointless since
        /// the link is gone, not just temporarily unreachable. Kept around (not deleted) rather
        /// than silently dropped, per AC-021's watch-out ("don't clear queued answers on
        /// `.linkRevoked` silently — surface state so the UI can explain"), so a future UI
        /// (AC-032) can render an honest "couldn't be delivered" state instead of "Sending…"
        /// forever, and so the offline retry loop skips it rather than hammering a dead link.
        case failed
    }

    /// Minted once, at compose time (`PendingAnswerStore.enqueue`), and never changed after —
    /// this is the idempotency key the write endpoint's `recordName = "pcf-" + submissionId`
    /// (AC-015) relies on to make a retried POST land on the same `PendingClipFeedback` record
    /// instead of creating a duplicate. `id` satisfies `Identifiable` for free list-diffing in
    /// AC-031/032's views.
    var id: String { submissionId }
    let submissionId: String
    let questionId: String
    var body: String
    let submittedAt: Date
    var state: State

    init(submissionId: String, questionId: String, body: String, submittedAt: Date, state: State) {
        self.submissionId = submissionId
        self.questionId = questionId
        self.body = body
        self.submittedAt = submittedAt
        self.state = state
    }
}

// MARK: - Retry Backoff

/// Pure delay calculation for the offline retry queue's exponential backoff (AC-021 scope). No
/// scheduling/`Task` loop lives here on purpose — AC-031/032's ViewModels own *when* to retry
/// (app foreground, launch); this only answers *how long to wait* for a given attempt number, so
/// it's trivially testable without simulating app lifecycle events.
nonisolated enum ClipRetryBackoff {
    /// `attempt` is 1-based (the 1st retry after an initial failed send). Doubles from `base` up
    /// to `maxDelay`, e.g. with the defaults: 2s, 4s, 8s, 16s, 30s, 30s, ...
    static func delay(
        forAttempt attempt: Int,
        base: Duration = .seconds(2),
        maxDelay: Duration = .seconds(30)
    ) -> Duration {
        guard attempt > 0 else { return base }
        let exponent = min(attempt - 1, 30) // guards against overflow on a runaway attempt count
        let multiplier = 1 << exponent
        let scaled = base * multiplier
        return min(scaled, maxDelay)
    }
}

// MARK: - Protocol

/// App Group-backed persistence for a guest's submitted-or-submitting answers: the source of
/// truth for both the optimistic echo (AC-031/032 render `.queued`/`.sent` entries as bubbles)
/// and the offline retry queue (AC-031/032 read `.queued` entries back out to retry them through
/// `ClipFeedbackSubmitting`). Must survive process relaunch — an in-memory-only conformance would
/// fail AC-021's "queue survives relaunch" acceptance criterion.
protocol PendingAnswerStoring: Sendable {
    /// Every locally-known answer, in insertion order. Includes both `.queued` and `.sent`
    /// entries — callers filter for what they need (queued ones to retry, all of them to render
    /// the optimistic echo).
    func allAnswers() async -> [PendingAnswer]

    /// Mints a fresh `submissionId` and persists a new `.queued` entry for one answer, at compose
    /// time (the moment the guest hits submit) — never re-called for a retry of the same answer;
    /// retries re-read the already-persisted entry via `allAnswers()` instead, which is what
    /// keeps the submissionId stable across attempts.
    @discardableResult
    func enqueue(questionId: String, body: String) async -> PendingAnswer

    /// Updates the body text of an existing entry in place — `submissionId`, `questionId`, and
    /// `state` are all left untouched. Used when the guest edits a draft after a failed submit,
    /// so a retry carries the corrected text under the *same* idempotency key rather than
    /// `submit()` minting a brand-new `submissionId` (which would duplicate-enqueue). A no-op if
    /// no entry has this `submissionId`.
    func amend(submissionId: String, body: String) async

    /// Atomically reuses the earliest `.queued` entry for `questionId` (amending its body if it
    /// differs from `body`) or, if none exists, enqueues a new `.queued` entry — the single
    /// source of truth for `ClipYourFeedbackViewModel.submit()`'s "reuse existing entry or
    /// enqueue a new one" decision. Doing this inside one actor-isolated call (rather than the
    /// caller snapshotting via `allAnswers()` and then separately calling `enqueue`/`amend`)
    /// closes a check-then-act race across the actor boundary: two overlapping calls for the
    /// same `questionId` can no longer both see "no queued entry yet" and both enqueue,
    /// producing the exact duplicate-`.queued`-entries-per-questionId state this store must
    /// never persist. If more than one `.queued` entry for `questionId` already exists on disk
    /// (e.g. from data written by a build that had this race), only the earliest is reused —
    /// every other one is marked `.failed` so it stops being retried instead of lingering as an
    /// orphan.
    @discardableResult
    func enqueueIfAbsent(questionId: String, body: String) async -> PendingAnswer

    /// Marks every entry whose `submissionId` is in `submissionIds` as `.sent`, after
    /// `ClipFeedbackSubmitting` confirms the endpoint wrote it. A no-op for any id that isn't
    /// currently `.queued` (e.g. already `.sent`, or unknown).
    func markSent(submissionIds: [String]) async

    /// Marks every entry whose `submissionId` is in `submissionIds` as `.failed`, after
    /// `ClipFeedbackSubmitting` reports `ClipFeedbackError.linkRevoked` for them — a deterministic,
    /// non-retryable rejection. The entries are kept (not deleted) so their state stays honest for
    /// a future UI rather than retrying forever against a dead link. A no-op for any id that isn't
    /// currently `.queued`.
    func markFailed(submissionIds: [String]) async

    /// Drops every `.sent` entry whose `questionId` is in `confirmedQuestionIds` — call this
    /// after a mirror fetch (`ClipSpaceRepositoring.fetchAnswers`) comes back with a
    /// `MirroredAnswer` for this guest's `guestId` on that question, per AC-021's scope. `.queued`
    /// entries are left untouched even if their `questionId` matches: they haven't been confirmed
    /// sent yet, so dropping them here would silently lose the guest's not-yet-delivered text.
    func dropConfirmedAnswers(confirmedQuestionIds: Set<String>) async
}

// MARK: - Live Implementation

/// `actor`-isolated so concurrent callers (a retry pass on launch racing a fresh submit from the
/// composer, for instance) can't interleave a read-modify-write on the backing file into a lost
/// update — the same reason `ClipSpaceRepository`'s in-memory cache is an actor. Backed by a
/// single JSON file in the shared App Group container (`group.xyz.nandamochammad.Reflect`, same
/// group `GuestIdentityStore` already writes to) rather than `UserDefaults`: this is an ordered
/// list of records, not a single blob, and a plain `[PendingAnswer]` array file keeps the
/// read-modify-write loop simple.
actor LivePendingAnswerStore: PendingAnswerStoring {

    // MARK: - Constants

    private let appGroupIdentifier = "group.xyz.nandamochammad.Reflect"
    private let fileName = "clip-pending-answers.json"
    private let logger = Logger(subsystem: "xyz.nandamochammad.Reflect.Clip", category: "PendingAnswerStore")

    // MARK: - State

    /// Loaded lazily on first access rather than in `init` so construction (a `ClipDIContainer`
    /// factory call) never touches disk — only the first real read/write does.
    private var cachedAnswers: [PendingAnswer]?

    // MARK: - Initialization

    init() {}

    // MARK: - PendingAnswerStoring

    func allAnswers() -> [PendingAnswer] {
        loadIfNeeded()
    }

    @discardableResult
    func enqueue(questionId: String, body: String) -> PendingAnswer {
        var answers = loadIfNeeded()
        let answer = PendingAnswer(
            submissionId: UUID().uuidString,
            questionId: questionId,
            body: body,
            submittedAt: Date(),
            state: .queued
        )
        answers.append(answer)
        persist(answers)
        return answer
    }

    func amend(submissionId: String, body: String) {
        var answers = loadIfNeeded()
        guard let index = answers.firstIndex(where: { $0.submissionId == submissionId }) else { return }
        guard answers[index].body != body else { return }
        answers[index].body = body
        persist(answers)
    }

    @discardableResult
    func enqueueIfAbsent(questionId: String, body: String) -> PendingAnswer {
        var answers = loadIfNeeded()
        let queuedIndices = answers.indices.filter {
            answers[$0].questionId == questionId && answers[$0].state == .queued
        }

        guard let firstIndex = queuedIndices.first else {
            let answer = PendingAnswer(
                submissionId: UUID().uuidString,
                questionId: questionId,
                body: body,
                submittedAt: Date(),
                state: .queued
            )
            answers.append(answer)
            persist(answers)
            return answer
        }

        var changed = false
        // Any additional `.queued` entries for this questionId are duplicates that must never
        // have been written together — reuse only the earliest and stop the rest from being
        // retried forever.
        for index in queuedIndices.dropFirst() {
            answers[index].state = .failed
            changed = true
        }
        if answers[firstIndex].body != body {
            answers[firstIndex].body = body
            changed = true
        }
        if changed {
            persist(answers)
        }
        return answers[firstIndex]
    }

    func markSent(submissionIds: [String]) {
        setState(.sent, forSubmissionIds: submissionIds)
    }

    func markFailed(submissionIds: [String]) {
        setState(.failed, forSubmissionIds: submissionIds)
    }

    private func setState(_ state: PendingAnswer.State, forSubmissionIds submissionIds: [String]) {
        guard !submissionIds.isEmpty else { return }
        var answers = loadIfNeeded()
        let idsToMark = Set(submissionIds)
        var changed = false
        for index in answers.indices where idsToMark.contains(answers[index].submissionId) {
            if answers[index].state != state {
                answers[index].state = state
                changed = true
            }
        }
        guard changed else { return }
        persist(answers)
    }

    func dropConfirmedAnswers(confirmedQuestionIds: Set<String>) {
        guard !confirmedQuestionIds.isEmpty else { return }
        var answers = loadIfNeeded()
        let originalCount = answers.count
        answers.removeAll { answer in
            answer.state == .sent && confirmedQuestionIds.contains(answer.questionId)
        }
        guard answers.count != originalCount else { return }
        persist(answers)
    }

    // MARK: - Private Helpers — Persistence

    private func loadIfNeeded() -> [PendingAnswer] {
        if let cachedAnswers {
            return cachedAnswers
        }
        let loaded = readFromDisk()
        cachedAnswers = loaded
        return loaded
    }

    private func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    private func readFromDisk() -> [PendingAnswer] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else {
            return []
        }
        guard let decoded = try? JSONDecoder().decode([PendingAnswer].self, from: data) else {
            logger.error("Pending-answer file exists but failed to decode — starting from an empty queue")
            return []
        }
        return decoded
    }

    /// Updates the in-memory cache first so every store method observes its own write
    /// immediately even if the disk write below fails (simulator quirks, missing entitlement) —
    /// mirroring `GuestIdentityStore`'s "a single-layer failure shouldn't strand the caller"
    /// stance. The tradeoff, same as that type's, is that a failed disk write here is silent
    /// beyond the log line: the next process launch would read stale (pre-mutation) state from
    /// disk since there is no App Group mirror layer for this data the way `GuestIdentityStore`
    /// has one for identity.
    private func persist(_ answers: [PendingAnswer]) {
        cachedAnswers = answers
        guard let url = fileURL() else {
            logger.error("App Group container unresolved for \(self.appGroupIdentifier, privacy: .public) — pending answers not persisted to disk")
            return
        }
        guard let data = try? JSONEncoder().encode(answers) else {
            logger.error("Failed to encode pending answers for persistence")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to write pending answers to disk — \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - DIContainer Factory

extension ClipDIContainer {
    func makePendingAnswerStore() -> PendingAnswerStoring {
        sharedPendingAnswerStore
    }
}
