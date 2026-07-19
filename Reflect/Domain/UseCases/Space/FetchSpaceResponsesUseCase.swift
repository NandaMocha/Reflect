import Foundation

protocol FetchSpaceResponsesUseCaseProtocol {
    func execute(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceResponse]
}

/// Passthrough to the repository's response fetch (cloud fetch + cache reconcile).
@MainActor
final class FetchSpaceResponsesUseCase: FetchSpaceResponsesUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceResponse] {
        try await repository.fetchResponses(for: reflection, in: space)
    }
}
