import CloudKit

protocol AcceptSpaceInviteUseCaseProtocol {
    func execute(metadata: CKShare.Metadata) async throws -> Space
}

/// Accepts an incoming share invitation (delivered by the SceneDelegate as
/// `CKShare.Metadata`) and returns the joined space.
@MainActor
final class AcceptSpaceInviteUseCase: AcceptSpaceInviteUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(metadata: CKShare.Metadata) async throws -> Space {
        try await repository.acceptInvite(metadata: metadata)
    }
}
