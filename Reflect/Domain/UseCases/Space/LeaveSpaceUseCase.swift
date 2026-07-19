import Foundation

protocol LeaveSpaceUseCaseProtocol {
    func execute(space: Space) async throws
}

/// Participant-only action. Guards `isOwner == false`: an owner leaving is nonsensical
/// (they'd orphan the space for everyone) — they must delete instead. Mirrors the
/// service's shared-DB lane assertion.
@MainActor
final class LeaveSpaceUseCase: LeaveSpaceUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(space: Space) async throws {
        guard !space.isOwner else {
            throw SpaceError.syncFailed("Owners can't leave their own space; delete it instead.")
        }
        try await repository.leaveSpace(space)
    }
}
