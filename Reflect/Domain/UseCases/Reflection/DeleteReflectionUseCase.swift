import Foundation

protocol DeleteReflectionUseCaseProtocol {
    func execute(reflection: Reflection) async throws
}

final class DeleteReflectionUseCase: DeleteReflectionUseCaseProtocol {
    private let reflectionRepository: ReflectionRepositoryProtocol

    init(
        reflectionRepository: ReflectionRepositoryProtocol
    ) {
        self.reflectionRepository = reflectionRepository
    }

    func execute(reflection: Reflection) async throws {
        try await reflectionRepository.delete(reflection)
    }
}
