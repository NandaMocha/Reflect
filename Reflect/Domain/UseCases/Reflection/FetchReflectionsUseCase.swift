import Foundation

protocol FetchReflectionsUseCaseProtocol {
    func execute() async throws -> [Reflection]
    func execute(id: UUID) async throws -> Reflection?
    func execute(learningId: UUID) async throws -> [Reflection]
    func executeFavorites() async throws -> [Reflection]
}

final class FetchReflectionsUseCase: FetchReflectionsUseCaseProtocol {
    private let repository: ReflectionRepositoryProtocol

    init(repository: ReflectionRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [Reflection] {
        try await repository.fetchAll()
    }

    func execute(id: UUID) async throws -> Reflection? {
        try await repository.fetch(id: id)
    }

    func execute(learningId: UUID) async throws -> [Reflection] {
        try await repository.fetchByLearning(learningId)
    }

    func executeFavorites() async throws -> [Reflection] {
        try await repository.fetchFavorites()
    }
}
