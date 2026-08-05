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
    /// `dropConfirmedAnswers` removes it, so the store only ever holds `.queued`/`.sent`.
    enum State: String, Codable, Sendable {
        /// Enqueued locally; either never POSTed yet or every POST attempt so far has failed.
        /// Still eligible for retry.
        case queued
        /// The write endpoint (AC-015) confirmed this `submissionId` was written. Kept around
        /// (rather than deleted immediately) so the optimistic echo still renders it until a
        /// `MirroredAnswer` shows up — deleting on `.sent` would reopen the exact gap the
        /// mitigation exists to close.
        case sent
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

    /// Marks every entry whose `submissionId` is in `submissionIds` as `.sent`, after
    /// `ClipFeedbackSubmitting` confirms the endpoint wrote it. A no-op for any id that isn't
    /// currently `.queued` (e.g. already `.sent`, or unknown).
    func markSent(submissionIds: [String]) async

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

    func markSent(submissionIds: [String]) {
        guard !submissionIds.isEmpty else { return }
        var answers = loadIfNeeded()
        let idsToMark = Set(submissionIds)
        var changed = false
        for index in answers.indices where idsToMark.contains(answers[index].submissionId) {
            if answers[index].state != .sent {
                answers[index].state = .sent
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
        LivePendingAnswerStore()
    }
}
