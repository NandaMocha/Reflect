import Foundation

protocol FetchSpaceReflectionsUseCaseProtocol {
    func execute(for space: Space) async throws -> [SpaceReflection]
}

/// Passthrough to the repository's reflection fetch (cloud fetch + cache reconcile).
@MainActor
final class FetchSpaceReflectionsUseCase: FetchSpaceReflectionsUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(for space: Space) async throws -> [SpaceReflection] {
        try await repository.fetchReflections(for: space)
    }
}
