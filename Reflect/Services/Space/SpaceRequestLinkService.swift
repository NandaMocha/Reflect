import CloudKit
import Foundation

/// Resolves a `/f/<token>` guest-feedback request link back to the owning Space's
/// `CKShare` — the full-app side of AC-014's universal-link handling. This is a
/// `records/lookup`-equivalent read of the public `TokenIndex` row AC-010 mints and
/// AC-011 keeps published, followed by a `CKShare.Metadata` fetch for the share URL it
/// points at. Public-DB only: `TokenIndex` is `_world`-readable by design (AC-H1), so
/// this never requires the current user to already be a participant of anything.
protocol SpaceRequestLinkServiceProtocol: Sendable {
    /// - Returns: the resolved `CKShare.Metadata` (whose `participantStatus` tells the
    ///   caller whether the current user already belongs to the space) plus the
    ///   `SpaceReflection` record name the link points at.
    /// - Throws: `SpaceRequestLinkError.invalidLink` for an absent/malformed token
    ///   (revoked link, deleted request, or a typo'd URL) — never a raw `CKError`, so
    ///   callers can show one friendly alert regardless of the underlying cause.
    func resolveMetadata(forToken token: String) async throws -> (metadata: CKShare.Metadata, reflectionID: String)
}

enum SpaceRequestLinkError: Error, LocalizedError {
    case invalidLink
    case network(String)
    case reflectionNotFound

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "This feedback link isn't valid anymore. It may have been revoked, or the request may have been deleted."
        case .network(let message):
            return "Couldn't open that link right now: \(message)"
        case .reflectionNotFound:
            return "Couldn't find that feedback request."
        }
    }
}

final class SpaceRequestLinkService: SpaceRequestLinkServiceProtocol {
    private let container = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")

    func resolveMetadata(forToken token: String) async throws -> (metadata: CKShare.Metadata, reflectionID: String) {
        let record = try await fetchTokenIndexRecord(token: token)

        guard let shareURLString = record[ClipMirrorField.shareURL] as? String,
              let shareURL = URL(string: shareURLString),
              let reflectionID = record[ClipMirrorField.reflectionID] as? String,
              !reflectionID.isEmpty else {
            throw SpaceRequestLinkError.invalidLink
        }

        let metadata = try await fetchShareMetadata(url: shareURL)
        return (metadata, reflectionID)
    }

    // MARK: - Private

    private func fetchTokenIndexRecord(token: String) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: ClipMirrorRecordName.tokenIndex(for: token))
        do {
            return try await container.publicCloudDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // No TokenIndex row for this token — revoked, deleted, or never existed.
            throw SpaceRequestLinkError.invalidLink
        } catch {
            throw SpaceRequestLinkError.network(error.localizedDescription)
        }
    }

    /// `CKFetchShareMetadataOperation` (not the deprecated
    /// `fetchShareMetadata(with:completionHandler:)`) wrapped in a continuation, matching
    /// the operation-based CloudKit style used throughout `Services/Space/`.
    private func fetchShareMetadata(url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            var metadata: CKShare.Metadata?
            var perShareError: Error?

            operation.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let value):
                    metadata = value
                case .failure(let error):
                    perShareError = error
                }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let metadata {
                        continuation.resume(returning: metadata)
                    } else {
                        continuation.resume(throwing: perShareError ?? SpaceRequestLinkError.invalidLink)
                    }
                case .failure(let error):
                    continuation.resume(throwing: perShareError ?? error)
                }
            }
            container.add(operation)
        }
    }
}
