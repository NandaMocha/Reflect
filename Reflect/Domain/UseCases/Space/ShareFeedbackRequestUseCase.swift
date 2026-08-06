import CloudKit
import Foundation

/// Mints (or reuses) a feedback request's guest-link token, publishes its public mirror,
/// and hands back the `https://nandamochammad.xyz/f/<token>` wrapper URL for the share
/// sheet — the owner-side half of AC-014 (universal-link resolution is the other half,
/// `ResolveRequestLinkUseCase`).
protocol ShareFeedbackRequestUseCaseProtocol {
    func execute(reflection: SpaceReflection, space: Space) async throws -> ShareFeedbackRequestUseCase.Result
}

enum ShareFeedbackRequestError: Error, LocalizedError {
    case notOwner
    case invalidLink

    var errorDescription: String? {
        switch self {
        case .notOwner:
            return "Only the space owner can share a guest-feedback link."
        case .invalidLink:
            return "Couldn't create a feedback link right now. Try again in a moment."
        }
    }
}

/// Depends on `SpaceCloudServiceProtocol` (AC-010's `ensureRequestToken`) and
/// `SpaceMirrorServiceProtocol` (AC-011's publish) directly rather than only through
/// `SpaceRepositoryProtocol` — neither the token mint nor the mirror publish has a cached
/// local model to reconcile, so there's nothing for the repository layer to own here.
/// `SpaceRepositoryProtocol` is used only for the one thing it does own: the space's raw
/// `CKShare` URL, offered alongside the wrapper link per the ticket's "alongside... the
/// raw CKShare URL" acceptance.
@MainActor
final class ShareFeedbackRequestUseCase: ShareFeedbackRequestUseCaseProtocol {

    /// `rawShareURL` is best-effort — a failure fetching the Space's own `CKShare` must
    /// never block the (already-succeeded) request link from being shared.
    struct Result {
        let requestLinkURL: URL
        let rawShareURL: URL?
    }

    private let cloudService: SpaceCloudServiceProtocol
    private let mirrorService: SpaceMirrorServiceProtocol
    private let repository: SpaceRepositoryProtocol

    init(
        cloudService: SpaceCloudServiceProtocol,
        mirrorService: SpaceMirrorServiceProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.cloudService = cloudService
        self.mirrorService = mirrorService
        self.repository = repository
    }

    func execute(reflection: SpaceReflection, space: Space) async throws -> Result {
        guard space.isOwner else { throw ShareFeedbackRequestError.notOwner }

        let token = try await cloudService.ensureRequestToken(for: reflection.id, in: space.zoneID)

        // Fire-and-forget-ish: the link is already good the moment the token exists (a
        // guest posting through the Clip lands in `PendingClipFeedback` regardless, per
        // AC-012's ingestion path). A publish failure here shouldn't block sharing — the
        // next owner sync republishes it (AC-011's own fire-and-forget hook) — but it's
        // logged rather than silently swallowed, per the repo's `try?` convention.
        do {
            try await mirrorService.publishMirrors(reflectionIDs: [reflection.id], zone: space.zoneID)
        } catch {
            #if DEBUG
            print("[ShareFeedbackRequestUseCase] mirror publish failed for \(reflection.id): \(error)")
            #endif
        }

        guard let requestLinkURL = URL(string: "https://nandamochammad.xyz/f/\(token)") else {
            throw ShareFeedbackRequestError.invalidLink
        }

        var rawShareURL: URL?
        do {
            rawShareURL = try await repository.shareForSpace(space).url
        } catch {
            #if DEBUG
            print("[ShareFeedbackRequestUseCase] raw CKShare URL fetch failed: \(error)")
            #endif
        }

        return Result(requestLinkURL: requestLinkURL, rawShareURL: rawShareURL)
    }
}
