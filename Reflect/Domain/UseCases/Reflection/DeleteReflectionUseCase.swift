import Foundation

protocol DeleteReflectionUseCaseProtocol {
    func execute(reflection: Reflection) async throws
}

final class DeleteReflectionUseCase: DeleteReflectionUseCaseProtocol {
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let hashtagRepository: HashtagRepositoryProtocol

    init(
        reflectionRepository: ReflectionRepositoryProtocol,
        hashtagRepository: HashtagRepositoryProtocol
    ) {
        self.reflectionRepository = reflectionRepository
        self.hashtagRepository = hashtagRepository
    }

    func execute(reflection: Reflection) async throws {
        try await reflectionRepository.delete(reflection)
        try await hashtagRepository.cleanupUnused()
    }
}
