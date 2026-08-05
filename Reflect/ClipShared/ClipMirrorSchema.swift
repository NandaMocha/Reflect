import Foundation
import Security

// MARK: - Record Type Names
//
// CloudKit public-database record types shared between the full app (`Reflect`) and the
// App Clip (`ReflectClip`). Strings here must match AC-H1's Console setup exactly — see
// docs/features/app-clip-tasks.md and docs/features/handoff-2026-08-05.md.
//
// `nonisolated` throughout: the Clip target builds with
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 6), which would otherwise silently
// pin every declaration in this file to the main actor. These are pure, stateless
// constants/helpers that later tickets (AC-011/012/015/020/021) call from off-main-actor
// contexts (e.g. parsing a public-DB HTTP response), so isolation must not be inferred —
// see the AC-001 review note this ticket was warned about.

/// Public-DB record types the app's `SpaceMirrorService` publishes to and the Clip's
/// `ClipSpaceRepository` reads from.
nonisolated enum ClipMirrorRecordType {
    /// Read-only mirror of a `SpaceReflection` (title/note/questions), keyed by
    /// `requestToken`. `_world` read; written only by the owner's app.
    static let mirroredRequest = "MirroredRequest"
    /// Read-only mirror of one `Answer`, keyed by `requestToken`. `_world` read;
    /// written only by the owner's app.
    static let mirroredAnswer = "MirroredAnswer"
    /// Public lookup: `tok-<token>` recordName -> which zone/reflection the token
    /// resolves to. `_world` read; written only by the owner's app.
    static let tokenIndex = "TokenIndex"
    /// A guest's in-flight submission, written by the server-side write endpoint (App
    /// Clips cannot write to CloudKit directly). No world read — server key + owner only.
    static let pendingClipFeedback = "PendingClipFeedback"
}

// MARK: - Field Keys

/// CKRecord field-key constants for the Clip mirror schema, grouped by the record type
/// that owns them. Mirrors the style of `SpaceRecordField` in `Services/Space/SpaceRecord.swift`.
nonisolated enum ClipMirrorField {
    // MirroredRequest
    static let requestToken = "requestToken"
    static let title = "title"
    static let note = "note"
    static let questionsJSON = "questionsJSON"
    static let thumbnail = "thumbnail"

    // MirroredAnswer (also uses `requestToken` above)
    static let questionId = "questionId"
    static let answerIndex = "answerIndex"
    static let authorDisplayName = "authorDisplayName"
    static let text = "text"
    static let guestId = "guestId"
    static let sourceAnswerRecordName = "sourceAnswerRecordName"

    // TokenIndex (also uses `requestToken`-derived recordName, see `ClipMirrorRecordName`)
    static let shareURL = "shareURL"
    static let reflectionID = "reflectionID"
    static let zoneOwnerName = "zoneOwnerName"

    // PendingClipFeedback (also uses `requestToken`, `questionId`, `guestId` above)
    static let guestName = "guestName"
    static let body = "body"
}

// MARK: - RecordName Conventions

/// `recordName` conventions for the Clip mirror's deterministic-name public records.
nonisolated enum ClipMirrorRecordName {
    static let tokenIndexPrefix = "tok-"
    static let pendingClipFeedbackPrefix = "pcf-"

    /// The `TokenIndex` recordName for a given request token — exactly `"tok-" + token`.
    /// AC-015's `records/lookup` depends on this being byte-for-byte stable.
    static func tokenIndex(for token: String) -> String {
        tokenIndexPrefix + token
    }

    /// The `PendingClipFeedback` recordName for one guest submission — exactly
    /// `"pcf-" + submissionId`. Must be deterministic in the client's `submissionId`
    /// (app-clip-plan.md's "deterministic submissionId idempotency" decision): a retry
    /// with the same `submissionId` has to land on the same record, not create a
    /// duplicate. AC-012 derives its ingested Answer's recordName as
    /// `"guest-" + submissionId` by stripping this same prefix, so the suffix must be
    /// exactly the client's `submissionId`, never a fresh random token.
    static func pendingClipFeedback(for submissionId: String) -> String {
        pendingClipFeedbackPrefix + submissionId
    }
}

// MARK: - Token Generation

/// Generates the per-request share token that fronts the whole guest-feedback flow.
nonisolated enum ClipToken {
    /// 16 cryptographically random bytes (128 bits), base64url-encoded with no padding.
    /// Deliberately **not** a UUID — UUIDs are not designed to resist guessing, and this
    /// token is the only thing standing between a guest link and someone else's feedback
    /// thread.
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return Data(bytes).base64URLEncodedString()
    }
}

nonisolated extension Data {
    /// Base64url (RFC 4648 §5) with padding stripped — safe to embed in a URL path
    /// segment (`/f/<token>`) without percent-encoding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Write-Endpoint DTOs (shared with AC-021)

/// One guest's answer to one question, as posted to the server-side write endpoint.
nonisolated struct ClipFeedbackAnswerDTO: Codable, Sendable, Equatable {
    var questionId: String
    var submissionId: String
    var body: String

    init(questionId: String, submissionId: String, body: String) {
        self.questionId = questionId
        self.submissionId = submissionId
        self.body = body
    }
}

/// Request body the Clip posts to the write endpoint (task 2.5) when a guest submits
/// feedback. The endpoint fans these out into one `PendingClipFeedback` record per
/// answer (AC-012 ingests them from there).
nonisolated struct ClipFeedbackSubmissionRequest: Codable, Sendable, Equatable {
    var requestToken: String
    var guestId: String
    var guestName: String
    var answers: [ClipFeedbackAnswerDTO]

    init(requestToken: String, guestId: String, guestName: String, answers: [ClipFeedbackAnswerDTO]) {
        self.requestToken = requestToken
        self.guestId = guestId
        self.guestName = guestName
        self.answers = answers
    }
}

/// Response from the write endpoint. Mirrors `clip-feedback.php`'s actual JSON shape:
/// `{"ok": true, "submitted": [...]}` on success, `{"ok": false, "error": "<code>",
/// "message": "<text>"}` on failure. AC-021 maps `error` codes (e.g. `"not_found"` /
/// `"gone"` -> `.linkRevoked`, `"rate_limited"` -> `.rateLimited) itself, so this DTO
/// surfaces the raw code rather than a pre-mapped local enum.
nonisolated struct ClipFeedbackSubmissionResponse: Codable, Sendable, Equatable {
    var ok: Bool
    var submitted: [String]?
    var error: String?
    var message: String?

    init(ok: Bool, submitted: [String]? = nil, error: String? = nil, message: String? = nil) {
        self.ok = ok
        self.submitted = submitted
        self.error = error
        self.message = message
    }
}
