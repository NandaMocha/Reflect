import Foundation

protocol FetchSpaceMembersUseCaseProtocol {
    func execute(for space: Space) async throws -> [SpaceMember]
}

/// Reads a space's participants off its `CKShare`.
@MainActor
final class FetchSpaceMembersUseCase: FetchSpaceMembersUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(for space: Space) async throws -> [SpaceMember] {
        try await repository.members(of: space)
    }
}
