import Foundation

protocol FetchSpacesUseCaseProtocol {
    func execute(forceRefresh: Bool) async throws -> [Space]
}

/// Passthrough to the repository's merged owned + joined fetch.
@MainActor
final class FetchSpacesUseCase: FetchSpacesUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(forceRefresh: Bool) async throws -> [Space] {
        try await repository.fetchSpaces(forceRefresh: forceRefresh)
    }
}
