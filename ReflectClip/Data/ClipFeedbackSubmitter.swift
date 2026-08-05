import Foundation

// MARK: - Errors

/// Failure modes for a guest-feedback submission POST, mapped from the write endpoint's HTTP
/// status per AC-021's scope (`docs/features/app-clip-tasks.md`). `scripts/server/clip-feedback.php`
/// (AC-015) is the source of truth for these statuses:
/// - `404`/`410` -> no/expired `TokenIndex` record (`token_not_found`) -> `.linkRevoked`.
/// - `429` -> per-IP or per-token rate limit tripped -> `.rateLimited`.
/// - everything else (validation 400s, `502` CloudKit-relay failures, transport errors,
///   malformed responses) collapses to `.network` — the composer's honest answer for any of
///   these is the same "will send when online" retry affordance, not a bespoke message per code.
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
            return "Couldn't send your feedback. It'll retry automatically."
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

// MARK: - DIContainer Factory

extension ClipDIContainer {
    func makeClipFeedbackSubmitter() -> ClipFeedbackSubmitting {
        ClipFeedbackSubmitter()
    }
}
