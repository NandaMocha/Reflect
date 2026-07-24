import Foundation

protocol MoveReflectionUseCaseProtocol {
    /// Reassigns `reflection.learning` to the learning with `toLearningId`. Throws
    /// `ReflectionError.notFound` / `.learningNotFound` if either ID is missing.
    func execute(reflectionId: UUID, toLearningId: UUID) async throws -> Reflection
}

final class MoveReflectionUseCase: MoveReflectionUseCaseProtocol {
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let learningRepository: LearningRepositoryProtocol

    init(
        reflectionRepository: ReflectionRepositoryProtocol,
        learningRepository: LearningRepositoryProtocol
    ) {
        self.reflectionRepository = reflectionRepository
        self.learningRepository = learningRepository
    }

    func execute(reflectionId: UUID, toLearningId: UUID) async throws -> Reflection {
        guard let reflection = try await reflectionRepository.fetch(id: reflectionId) else {
            throw ReflectionError.notFound
        }
        guard let learning = try await learningRepository.fetch(id: toLearningId) else {
            throw ReflectionError.learningNotFound
        }

        reflection.learning = learning
        reflection.updatedAt = Date()
        try await reflectionRepository.update(reflection)
        return reflection
    }
}
