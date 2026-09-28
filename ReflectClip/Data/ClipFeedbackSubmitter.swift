import Foundation
import os

// MARK: - Errors

/// Failure modes for a guest-feedback submission POST, mapped from the write endpoint's HTTP
/// status per AC-021's scope (`docs/features/app-clip-tasks.md`). `scripts/server/clip-feedback.php`
/// (AC-015) is the source of truth for these statuses:
/// - `404`/`410` -> no/expired `TokenIndex` record (`token_not_found`) -> `.linkRevoked`.
/// - `429` -> per-IP or per-token rate limit tripped -> `.rateLimited`.
/// - everything else (validation 400s, `502` CloudKit-relay failures, transport errors,
///   malformed responses) collapses to `.network` — the composer's honest answer for any of
///   these is the same "will send when online" retry affordance, not a bespoke message per code.
///
/// `errorDescription` only states what failed. What happens next (saved on device, retried
/// automatically the next time the Clip opens or comes back to the foreground via
/// `ClipPendingAnswerRetrier`) is the composer banner's job, so this copy never promises a
/// background retry that isn't running.
enum ClipFeedbackError: Error, LocalizedError, Sendable {
    /// The request's link is gone (unknown or revoked `TokenIndex`). Retrying won't help —
    /// per AC-021's watch-out, callers must surface this rather than silently keep retrying or
    /// silently drop the queued answers.
    case linkRevoked
    case rateLimited
    case network

    var errorDescription: String? {
        switch self {
        case .linkRevoked:
            return "This feedback link is no longer active."
        case .rateLimited:
            return "Too many requests. Try again in a moment."
        case .network:
            return "Couldn't send your feedback."
        }
    }
}

// MARK: - Protocol

/// Posts guest answers to the server-side write endpoint (`clip-feedback.php`, AC-015). The App
/// Clip has no CloudKit write credentials of its own — this is the only path a guest's answer
/// takes off-device (see `app-clip-plan.md`'s "Write path" decision).
///
/// `submissionId` on each `ClipFeedbackAnswerDTO` in the request must already be minted by the
/// caller and stay stable across retries — `PendingAnswerStore.enqueue` is that minting point.
/// This type never generates its own; it only transports whatever `ClipFeedbackSubmissionRequest`
/// it's given, so a caller retrying the exact same request lands on the exact same
/// `PendingClipFeedback` records server-side (`recordName = "pcf-" + submissionId`,
/// update-or-create) instead of creating duplicates.
protocol ClipFeedbackSubmitting: Sendable {
    /// Submits one batch of answers (1–5, matching the endpoint's per-call cap). Returns the
    /// `submissionId`s the server confirmed were written — callers mark exactly those
    /// `PendingAnswerStore` entries `.sent`. Throws `ClipFeedbackError` on any failure; none of
    /// the batch is presumed sent when this throws.
    func submit(_ request: ClipFeedbackSubmissionRequest) async throws -> [String]
}

// MARK: - Live Implementation

/// Plain `URLSession` POST to `https://nandamochammad.xyz/clip-feedback.php`. Deliberately no
/// retry/backoff logic in here — that lives in the caller (driven by `PendingAnswerStore`'s
/// queued entries), so this type stays a thin, easily-testable transport.
final class ClipFeedbackSubmitter: ClipFeedbackSubmitting, Sendable {

    // MARK: - Dependencies

    private let session: URLSession
    private let endpoint: URL

    // MARK: - Initialization

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://nandamochammad.xyz/clip-feedback.php")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    // MARK: - ClipFeedbackSubmitting

    func submit(_ request: ClipFeedbackSubmissionRequest) async throws -> [String] {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            // Encoding a plain Codable DTO of strings can't realistically fail, but a thrown
            // encoder error is still a "we couldn't send this" outcome for the caller, not a
            // distinct case worth its own enum member per AC-021's scope (`else .network`).
            throw ClipFeedbackError.network
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ClipFeedbackError.network
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClipFeedbackError.network
        }

        switch httpResponse.statusCode {
        case 404, 410:
            throw ClipFeedbackError.linkRevoked
        case 429:
            throw ClipFeedbackError.rateLimited
        case 200:
            return try Self.parseSubmitted(from: data, fallback: request.answers.map(\.submissionId))
        default:
            throw ClipFeedbackError.network
        }
    }

    // MARK: - Private Helpers

    private static func parseSubmitted(from data: Data, fallback: [String]) throws -> [String] {
        guard let decoded = try? JSONDecoder().decode(ClipFeedbackSubmissionResponse.self, from: data),
              decoded.ok else {
            // HTTP 200 with a body that isn't the success shape the endpoint documents is a
            // server contract violation, not a guest-facing distinction worth its own case —
            // treat it the same as any other unexpected failure.
            throw ClipFeedbackError.network
        }
        // `submitted` mirrors exactly the submissionIds the endpoint wrote (see
        // `clip-feedback.php`'s response contract). Falling back to the request's own
        // submissionIds only guards against a future server response that omits the field while
        // still reporting `ok: true`; it is never expected to trigger against the current
        // endpoint.
        return decoded.submitted ?? fallback
    }
}

// MARK: - Automatic Retry

/// The offline retry loop AC-021 documents: re-POSTs every `.queued` `PendingAnswerStore` entry
/// when the Clip launches or returns to the foreground (`ReflectClipApp`), so a guest who
/// submitted offline and left doesn't depend on reopening the composer and tapping Retry.
///
/// One pass = up to `maxAttempts` tries, spaced by `ClipRetryBackoff`. Every try re-reads the
/// store, so it always resends the stored `submissionId`s (the idempotency contract) and skips
/// anything the composer already delivered meanwhile. A pass stops early on success or
/// `.linkRevoked`; if it runs out of attempts the entries stay `.queued` for the next trigger.
@MainActor
final class ClipPendingAnswerRetrier {

    // MARK: - State

    private var retryTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let session: ClipSession
    private let submitter: ClipFeedbackSubmitting
    private let pendingAnswerStore: PendingAnswerStoring
    private let installContinuityStore: ClipInstallContinuityStoring
    private let maxAttempts: Int
    private let logger = Logger(subsystem: "xyz.nandamochammad.Reflect.Clip", category: "ClipPendingAnswerRetrier")

    /// Matches `MAX_ANSWERS_PER_CALL` in `scripts/server/clip-feedback.php`.
    private static let maxAnswersPerCall = 5

    // MARK: - Initialization

    init(
        session: ClipSession,
        submitter: ClipFeedbackSubmitting,
        pendingAnswerStore: PendingAnswerStoring,
        installContinuityStore: ClipInstallContinuityStoring,
        maxAttempts: Int = 5
    ) {
        self.session = session
        self.submitter = submitter
        self.pendingAnswerStore = pendingAnswerStore
        self.installContinuityStore = installContinuityStore
        self.maxAttempts = maxAttempts
    }

    // MARK: - Actions

    /// Starts a retry pass unless one is already running. Safe to call on every launch,
    /// foreground and identity change — a no-op when nothing is queued or no guest identity is
    /// known yet (the endpoint requires `guestId` + `guestName`).
    func retryQueuedAnswers() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            await self?.runRetryPass()
            self?.retryTask = nil
        }
    }

    // MARK: - Private Helpers

    private func runRetryPass() async {
        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else { return }
            guard let outcome = await attemptDelivery() else { return }
            switch outcome {
            case .delivered, .linkRevoked:
                return
            case .transientFailure:
                guard attempt < maxAttempts else {
                    logger.info("Queued answers still unsent after \(attempt, privacy: .public) attempts — waiting for the next launch/foreground")
                    return
                }
                try? await Task.sleep(for: ClipRetryBackoff.delay(forAttempt: attempt))
            }
        }
    }

    private enum AttemptOutcome {
        case delivered
        case linkRevoked
        case transientFailure
    }

    /// One try over every `.queued` entry. `nil` means there was nothing to send (empty queue or
    /// no identity yet), which ends the pass.
    private func attemptDelivery() async -> AttemptOutcome? {
        guard let identity = session.guestIdentity else { return nil }
        let queued = await pendingAnswerStore.allAnswers().filter { $0.state == .queued }
        guard !queued.isEmpty else { return nil }

        var sentAny = false
        var sawTransientFailure = false
        var revokedCurrentLink = false

        for (token, answers) in Self.groupByRequestToken(queued, fallbackToken: session.requestToken) {
            for batch in Self.chunked(answers, size: Self.maxAnswersPerCall) {
                let request = ClipFeedbackSubmissionRequest(
                    requestToken: token,
                    guestId: identity.guestId.uuidString,
                    guestName: identity.displayName,
                    answers: batch.map {
                        ClipFeedbackAnswerDTO(questionId: $0.questionId, submissionId: $0.submissionId, body: $0.body)
                    }
                )
                do {
                    let sentIds = try await submitter.submit(request)
                    await pendingAnswerStore.markSent(submissionIds: sentIds)
                    sentAny = sentAny || !sentIds.isEmpty
                } catch ClipFeedbackError.linkRevoked {
                    // Same handling as the composer: a dead link is not retryable, so stop
                    // retrying these entries but keep them for the "couldn't be delivered" UI.
                    await pendingAnswerStore.markFailed(submissionIds: batch.map(\.submissionId))
                    revokedCurrentLink = revokedCurrentLink || token == session.requestToken
                } catch {
                    logger.error("Automatic retry failed — \(String(describing: error), privacy: .public)")
                    sawTransientFailure = true
                }
            }
        }

        if sentAny {
            // AC-040: same durable signal the composer records on its own successful send.
            installContinuityStore.recordAnswerSent()
        }
        if revokedCurrentLink {
            session.markLinkInvalid()
            return .linkRevoked
        }
        if sentAny {
            // The composer still shows the answers it failed to send, and a second tap on Send
            // would mint a new `submissionId` now that the entries are `.sent` — move on exactly
            // like the composer's own successful submit does. A no-op outside `.compose`.
            session.advanceToAllFeedback()
        }
        return sawTransientFailure ? .transientFailure : .delivered
    }

    /// Groups entries by the request they were composed against, keeping insertion order. Entries
    /// written before `PendingAnswer.requestToken` existed fall back to the current session's
    /// token; they're skipped if no invocation has resolved yet.
    private static func groupByRequestToken(
        _ answers: [PendingAnswer],
        fallbackToken: String?
    ) -> [(token: String, answers: [PendingAnswer])] {
        var groups: [(token: String, answers: [PendingAnswer])] = []
        for answer in answers {
            guard let token = answer.requestToken ?? fallbackToken else { continue }
            if let index = groups.firstIndex(where: { $0.token == token }) {
                groups[index].answers.append(answer)
            } else {
                groups.append((token, [answer]))
            }
        }
        return groups
    }

    private static func chunked(_ answers: [PendingAnswer], size: Int) -> [[PendingAnswer]] {
        stride(from: 0, to: answers.count, by: size).map {
            Array(answers[$0..<min($0 + size, answers.count)])
        }
    }
}

// MARK: - DIContainer Factory

extension ClipDIContainer {
    func makeClipFeedbackSubmitter() -> ClipFeedbackSubmitting {
        ClipFeedbackSubmitter()
    }

    func makeClipPendingAnswerRetrier() -> ClipPendingAnswerRetrier {
        ClipPendingAnswerRetrier(
            session: session,
            submitter: makeClipFeedbackSubmitter(),
            pendingAnswerStore: makePendingAnswerStore(),
            installContinuityStore: makeClipInstallContinuityStore()
        )
    }
}
