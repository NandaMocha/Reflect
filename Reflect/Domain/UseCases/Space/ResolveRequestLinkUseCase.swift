import CloudKit
import Foundation

/// Resolves a `/f/<token>` universal-link open into a navigable
/// `SpaceThreadDeepLink` — AC-014's guest-side/full-app half. Mirrors
/// `AcceptSpaceInviteUseCase`'s existing warm/cold-launch pattern (a delegate stashes
/// something in `SpaceInviteInbox`, `MainTabView` drains and resolves it), but this one
/// starts from a bare token rather than an already-known `CKShare.Metadata`.
protocol ResolveRequestLinkUseCaseProtocol {
    func execute(token: String) async throws -> SpaceThreadDeepLink
}

@MainActor
final class ResolveRequestLinkUseCase: ResolveRequestLinkUseCaseProtocol {
    private let linkService: SpaceRequestLinkServiceProtocol
    private let acceptUseCase: AcceptSpaceInviteUseCaseProtocol
    private let repository: SpaceRepositoryProtocol

    init(
        linkService: SpaceRequestLinkServiceProtocol,
        acceptUseCase: AcceptSpaceInviteUseCaseProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.linkService = linkService
        self.acceptUseCase = acceptUseCase
        self.repository = repository
    }

    func execute(token: String) async throws -> SpaceThreadDeepLink {
        let (metadata, reflectionID) = try await linkService.resolveMetadata(forToken: token)

        // Already a member of the space this link belongs to: resolve it from what we
        // already have instead of re-running `CKAcceptSharesOperation` — the "already-
        // member open deep-links without re-accepting" acceptance criterion. (Re-accepting
        // an already-accepted share is documented as a harmless no-op, so this is a UX/
        // efficiency choice, not a correctness requirement — but it keeps the accept path
        // reserved for opens that actually need it.)
        let space: Space
        if metadata.participantStatus == .accepted, let existing = try? await existingSpace(matching: metadata) {
            space = existing
        } else {
            space = try await acceptUseCase.execute(metadata: metadata)
        }

        let reflections = try await repository.fetchReflections(for: space)
        guard let reflection = reflections.first(where: { $0.id == reflectionID }) else {
            throw SpaceRequestLinkError.reflectionNotFound
        }

        return SpaceThreadDeepLink(space: space, reflection: reflection)
    }

    // MARK: - Private

    /// Finds the already-joined `Space` a `CKShare.Metadata` we're already a participant
    /// of belongs to, by matching its root record's zone. Cache-first, falling back to one
    /// forced refresh — a fresh install that only just joined via the system share sheet
    /// (rather than this flow) may not have it cached yet.
    private func existingSpace(matching metadata: CKShare.Metadata) async throws -> Space? {
        guard let rootRecordID = metadata.hierarchicalRootRecordID else { return nil }
        if let match = repository.cachedSpaces().first(where: { matches($0, rootRecordID) }) {
            return match
        }
        let fetched = try await repository.fetchSpaces(forceRefresh: true)
        return fetched.first(where: { matches($0, rootRecordID) })
    }

    private func matches(_ space: Space, _ rootRecordID: CKRecord.ID) -> Bool {
        space.zoneID.zoneName == rootRecordID.zoneID.zoneName
            && space.zoneID.ownerName == rootRecordID.zoneID.ownerName
    }
}
