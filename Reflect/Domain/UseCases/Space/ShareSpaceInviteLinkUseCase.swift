import Foundation

protocol ShareSpaceInviteLinkUseCaseProtocol {
    func execute(for space: Space) async throws -> URL
}

/// Produces the space's open invite link — a URL the owner can paste anywhere, which joins
/// whoever opens it to that one space without needing to be added as a named participant
/// first. Ensures the underlying `CKShare` is public before handing the URL back, so spaces
/// created before invite links existed are migrated on first use.
@MainActor
final class ShareSpaceInviteLinkUseCase: ShareSpaceInviteLinkUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(for space: Space) async throws -> URL {
        // Mirrors the server-side rule so a participant gets a clear domain error instead of
        // a raw CloudKit permission failure from deep in the save.
        guard space.isOwner else { throw SpaceError.notOwner }
        return try await repository.publicInviteLink(for: space)
    }
}
