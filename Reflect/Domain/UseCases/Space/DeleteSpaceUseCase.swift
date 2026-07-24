import Foundation

protocol DeleteSpaceUseCaseProtocol {
    func execute(space: Space) async throws
}

/// Owner-only destructive action. The `isOwner` guard is the last line of defense before
/// the repository/service tears down the zone for every participant — do not rely on the
/// UI having hidden Delete on joined rows.
@MainActor
final class DeleteSpaceUseCase: DeleteSpaceUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(space: Space) async throws {
        guard space.isOwner else { throw SpaceError.notOwner }
        try await repository.deleteSpace(space)
    }
}
