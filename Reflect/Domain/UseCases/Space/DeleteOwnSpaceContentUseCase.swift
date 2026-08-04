import Foundation

protocol DeleteOwnSpaceContentUseCaseProtocol {
    func execute(reflection: SpaceReflection, in space: Space) async throws
    func execute(response: SpaceResponse, in space: Space) async throws
    func execute(answer: SpaceAnswer, in space: Space) async throws
}

/// Deletes the user's own reflection or response. The `isMine` guard is the ONLY thing
/// between the UI and deleting someone else's content — CloudKit does not enforce
/// per-record authorship in a shared zone (plan §11.2). Treat a missing guard as a bug.
@MainActor
final class DeleteOwnSpaceContentUseCase: DeleteOwnSpaceContentUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(reflection: SpaceReflection, in space: Space) async throws {
        guard reflection.isMine else { throw SpaceError.notAuthor }
        try await repository.deleteContent(id: reflection.id, in: space)
    }

    func execute(response: SpaceResponse, in space: Space) async throws {
        guard response.isMine else { throw SpaceError.notAuthor }
        try await repository.deleteContent(id: response.id, in: space)
    }

    func execute(answer: SpaceAnswer, in space: Space) async throws {
        guard answer.isMine else { throw SpaceError.notAuthor }
        try await repository.deleteContent(id: answer.id, in: space)
    }
}
