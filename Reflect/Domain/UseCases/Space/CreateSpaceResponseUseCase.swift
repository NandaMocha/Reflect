import Foundation

protocol CreateSpaceResponseUseCaseProtocol {
    func execute(to reflection: SpaceReflection, in space: Space, body: String) async throws -> SpaceResponse
}

/// Validates a response body (1...max) before posting it. Multiple responses per member
/// are allowed (plan locked decision #6) — no uniqueness check.
@MainActor
final class CreateSpaceResponseUseCase: CreateSpaceResponseUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(to reflection: SpaceReflection, in space: Space, body: String) async throws -> SpaceResponse {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpaceError.bodyRequired }
        guard trimmed.count <= Constants.Limits.spaceResponseMaxLength else { throw SpaceError.bodyTooLong }

        return try await repository.createResponse(to: reflection, in: space, body: trimmed)
    }
}
