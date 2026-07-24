import Foundation

protocol EditOwnSpaceResponseUseCaseProtocol {
    func execute(_ response: SpaceResponse, in space: Space, body: String) async throws -> SpaceResponse
}

/// Edits the body of the user's own response. Guards `isMine` (the authorship boundary,
/// no server enforcement) and re-validates the body length, mirroring create.
@MainActor
final class EditOwnSpaceResponseUseCase: EditOwnSpaceResponseUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(_ response: SpaceResponse, in space: Space, body: String) async throws -> SpaceResponse {
        guard response.isMine else { throw SpaceError.notAuthor }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpaceError.bodyRequired }
        guard trimmed.count <= Constants.Limits.spaceResponseMaxLength else { throw SpaceError.bodyTooLong }

        return try await repository.updateResponse(response, in: space, body: trimmed)
    }
}
