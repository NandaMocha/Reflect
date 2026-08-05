import CloudKit
import Foundation

// MARK: - Domain Model

/// A read-only snapshot of a guest-feedback request, as seen through the public-DB mirror
/// (AC-010's `MirroredRequest`, published by AC-011's `SpaceMirrorService`). Distinct from the
/// app-side `SpaceReflection` because the Clip never has zone/share context — only what the
/// owner's app chose to publish.
struct ClipRequest: Sendable, Equatable {
    let requestToken: String
    let title: String
    let note: String?
    let questions: [SpaceQuestion]
    let thumbnailData: Data?
}

// MARK: - Errors

enum ClipSpaceError: Error, LocalizedError, Sendable {
    /// No `MirroredRequest` exists for the token — a malformed link, a revoked/expired one,
    /// or one whose mirror publish (AC-011) simply hasn't landed yet.
    case invalidLink
    case network
    case iCloudUnavailable
    /// A record was found but a required field didn't decode into something usable.
    case malformedData

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "This feedback link isn't valid or has expired."
        case .network:
            return "Couldn't reach iCloud. Check your connection and try again."
        case .iCloudUnavailable:
            return "iCloud is temporarily unavailable. Try again in a moment."
        case .malformedData:
            return "This feedback request couldn't be read."
        }
    }
}

// MARK: - Protocol

protocol ClipSpaceRepositoring: Sendable {
    /// Looks up the `MirroredRequest` for `token` and decodes it. Throws `.invalidLink` when
    /// no record exists. Anonymous (no-iCloud) users can read the public DB fine — this never
    /// gates on account status; `.iCloudUnavailable` only surfaces when CloudKit itself errors
    /// that way.
    func fetchRequest(token: String) async throws -> ClipRequest

    /// Fetches every `MirroredAnswer` for `token`, ordered by question then submission order.
    /// The mirror carries no notion of "current user", so the caller supplies `ownGuestId` to
    /// mark which answers are the calling guest's own (`SpaceAnswer.isMine`).
    func fetchAnswers(token: String, ownGuestId: String) async throws -> [SpaceAnswer]
}

// MARK: - Live Implementation

/// Public-DB read path for the Clip: `CKContainer(identifier:
/// "iCloud.xyz.nandamochammad.Reflect").publicCloudDatabase`, read-only. Writes never happen
/// here — an App Clip has no credentials for someone else's private data, so guest submissions
/// go through the server-side endpoint instead (AC-021/AC-012).
///
/// Deliberately independent of `SwiftData`, `SpaceCloudService`, and the full app's
/// `DIContainer` — this type must build and run standalone inside `ReflectClip`.
final class ClipSpaceRepository: ClipSpaceRepositoring, Sendable {

    // MARK: - Dependencies

    private let database: CKDatabase
    private let cache: ClipSpaceCache

    // MARK: - Initialization

    init(containerIdentifier: String = "iCloud.xyz.nandamochammad.Reflect") {
        self.database = CKContainer(identifier: containerIdentifier).publicCloudDatabase
        self.cache = ClipSpaceCache()
    }

    // MARK: - ClipSpaceRepositoring

    func fetchRequest(token: String) async throws -> ClipRequest {
        if let cached = await cache.request(for: token) {
            return cached
        }

        let record = try await fetchSingleRecord(
            recordType: ClipMirrorRecordType.mirroredRequest,
            token: token
        )
        let request = try Self.mapRequest(record, token: token)
        await cache.store(request)
        return request
    }

    func fetchAnswers(token: String, ownGuestId: String) async throws -> [SpaceAnswer] {
        let predicate = NSPredicate(format: "%K == %@", ClipMirrorField.requestToken, token)
        let query = CKQuery(recordType: ClipMirrorRecordType.mirroredAnswer, predicate: predicate)
        // "group by questionId, answerIndex order" (AC-020 scope) — a stable two-key sort
        // gives callers a ready-to-render order without a separate grouping pass; grouping by
        // `questionId` (e.g. `Dictionary(grouping:by:)`) is left to the caller since the
        // return type stays a flat `[SpaceAnswer]`.
        query.sortDescriptors = [
            NSSortDescriptor(key: ClipMirrorField.questionId, ascending: true),
            NSSortDescriptor(key: ClipMirrorField.answerIndex, ascending: true)
        ]

        let matches: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (matches, _) = try await database.records(matching: query)
        } catch {
            throw Self.mapCKError(error)
        }

        return matches.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return Self.mapAnswer(record, ownGuestId: ownGuestId)
        }
    }

    // MARK: - Private Helpers

    private func fetchSingleRecord(recordType: String, token: String) async throws -> CKRecord {
        let predicate = NSPredicate(format: "%K == %@", ClipMirrorField.requestToken, token)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let matches: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (matches, _) = try await database.records(matching: query, resultsLimit: 1)
        } catch {
            throw Self.mapCKError(error)
        }

        guard let first = matches.first else {
            throw ClipSpaceError.invalidLink
        }
        switch first.1 {
        case .success(let record):
            return record
        case .failure(let error):
            throw Self.mapCKError(error)
        }
    }

    private static func mapRequest(_ record: CKRecord, token: String) throws -> ClipRequest {
        guard let title = record[ClipMirrorField.title] as? String else {
            throw ClipSpaceError.malformedData
        }

        // `SpaceQuestion.decodeJSON` already ignores unknown keys (plain `Decodable`
        // synthesis), which satisfies AC-020's "decoding tolerates unknown JSON keys".
        let questionsJSON = record[ClipMirrorField.questionsJSON] as? String ?? "[]"
        let questions = SpaceQuestion.decodeJSON(questionsJSON)

        // Tolerant asset read — same rationale as `SpaceRecordMapper.spaceReflection(from:)`
        // in the full app: a missing/expired staging file degrades to text-only rather than
        // failing the whole fetch, so the guest still sees the request even without a
        // thumbnail.
        var thumbnailData: Data?
        if let asset = record[ClipMirrorField.thumbnail] as? CKAsset, let url = asset.fileURL {
            thumbnailData = try? Data(contentsOf: url)
        }

        return ClipRequest(
            requestToken: token,
            title: title,
            note: record[ClipMirrorField.note] as? String,
            questions: questions,
            thumbnailData: thumbnailData
        )
    }

    private static func mapAnswer(_ record: CKRecord, ownGuestId: String) -> SpaceAnswer? {
        guard let questionId = record[ClipMirrorField.questionId] as? String,
              let text = record[ClipMirrorField.text] as? String else {
            return nil
        }

        let guestId = record[ClipMirrorField.guestId] as? String
        let requestToken = record[ClipMirrorField.requestToken] as? String ?? ""
        let authorDisplayName = record[ClipMirrorField.authorDisplayName] as? String

        return SpaceAnswer(
            // `MirroredAnswer` has no field of its own for "the source Answer's identity" —
            // `sourceAnswerRecordName` is exactly that (see `ClipMirrorField`), so it's the
            // stable id here, falling back to the mirror record's own name only if a publish
            // predates that field being set.
            id: (record[ClipMirrorField.sourceAnswerRecordName] as? String) ?? record.recordID.recordName,
            // The mirror schema carries no separate `reflectionID` field — every
            // `MirroredAnswer` for a given request already scopes to exactly one reflection
            // (one request == one token == one reflection), so the request token is a stable,
            // unique stand-in that satisfies the shared `SpaceAnswer` entity's non-optional
            // `reflectionID`.
            reflectionID: requestToken,
            questionId: questionId,
            text: text,
            imageData: nil,
            authorRecordName: nil,
            authorDisplayName: authorDisplayName,
            createdAt: record.creationDate,
            modifiedAt: record.modificationDate,
            isMine: guestId != nil && guestId == ownGuestId,
            guestId: guestId,
            // `MirroredAnswer` doesn't mirror a separate `guestName` field (only
            // `authorDisplayName`); reuse that as the guest's display name so `SpaceAnswer`'s
            // `guestName`/`isGuest` pairing still means what its doc comment says.
            guestName: guestId != nil ? authorDisplayName : nil
        )
    }

    private static func mapCKError(_ error: Error) -> ClipSpaceError {
        guard let ckError = error as? CKError else {
            return .network
        }
        switch ckError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .iCloudUnavailable
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .network
        case .unknownItem:
            return .invalidLink
        default:
            return .network
        }
    }
}

// MARK: - In-Memory Cache

/// Actor-isolated cache for `ClipRequest` lookups, keyed by token. Per AC-020's scope
/// ("in-memory cache only") — no persistence, cleared on process death; fine since a Clip
/// process is short-lived and a relaunch just re-fetches. Answers aren't cached: the composer
/// flow expects fresh reads (new guest submissions arriving between polls).
private actor ClipSpaceCache {
    private var requests: [String: ClipRequest] = [:]

    func request(for token: String) -> ClipRequest? {
        requests[token]
    }

    func store(_ request: ClipRequest) {
        requests[request.requestToken] = request
    }
}

// MARK: - DIContainer Factory

extension ClipDIContainer {
    func makeClipSpaceRepository() -> ClipSpaceRepositoring {
        ClipSpaceRepository()
    }
}
