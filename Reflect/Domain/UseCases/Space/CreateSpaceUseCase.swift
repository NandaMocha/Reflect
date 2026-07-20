import Foundation

protocol CreateSpaceUseCaseProtocol {
    func execute(name: String, detail: String?, emoji: String?) async throws -> Space
}

/// Validates the space name (the last line of defense — not the ViewModel) before
/// delegating creation to the repository.
@MainActor
final class CreateSpaceUseCase: CreateSpaceUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(name: String, detail: String?, emoji: String?) async throws -> Space {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw SpaceError.nameRequired }
        guard trimmedName.count <= Constants.Limits.spaceNameMaxLength else { throw SpaceError.nameTooLong }

        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await repository.createSpace(
            name: trimmedName,
            detail: (trimmedDetail?.isEmpty ?? true) ? nil : trimmedDetail,
            emoji: emoji
        )
    }
}
