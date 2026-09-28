import Foundation

protocol DeleteOwnSpaceContentUseCaseProtocol {
    func execute(reflection: SpaceReflection, in space: Space) async throws
    func execute(answer: SpaceAnswer, in space: Space) async throws
}

/// Deletes the user's own reflection or response — or, for an answer, a guest's response if the
/// current user owns the space (AC-013 moderation affordance for App Clip submissions). The
/// guard on each `execute` is the ONLY thing between the UI and deleting someone else's content
/// — CloudKit does not enforce per-record authorship in a shared zone (plan §11.2). Treat a
/// missing or loosened guard as a bug; extend it explicitly, never bypass it.
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

    func execute(answer: SpaceAnswer, in space: Space) async throws {
        // Own answers, always. Guest answers only when the current user owns the space —
        // nothing else. Do not widen this beyond the two explicit cases.
        guard answer.isMine || (answer.isGuest && space.isOwner) else { throw SpaceError.notAuthor }
        try await repository.deleteContent(id: answer.id, in: space)
    }
}
