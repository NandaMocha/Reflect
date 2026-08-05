import Foundation
import UIKit

protocol AnswerWriteUseCaseProtocol {
    func create(to reflection: SpaceReflection, in space: Space, questionId: String, text: String, image: UIImage?) async throws -> SpaceAnswer
    func update(answer: SpaceAnswer, in space: Space, text: String, image: UIImage?) async throws -> SpaceAnswer
}

/// Validates answer text (1...max) before creating or replacing the caller's answer to a
/// question. An attached image is compressed hard (`.low`: max 800px, JPEG 0.3), matching
/// `CreateSpaceReflectionUseCase`'s pipeline, so shared-space payloads stay small.
@MainActor
final class AnswerWriteUseCase: AnswerWriteUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol
    private let imageService: ImageProcessingServiceProtocol

    init(repository: SpaceRepositoryProtocol, imageService: ImageProcessingServiceProtocol) {
        self.repository = repository
        self.imageService = imageService
    }

    func create(to reflection: SpaceReflection, in space: Space, questionId: String, text: String, image: UIImage?) async throws -> SpaceAnswer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpaceError.bodyRequired }
        guard trimmed.count <= Constants.Limits.spaceResponseMaxLength else { throw SpaceError.bodyTooLong }

        var imageData: Data?
        if let image {
            imageData = await imageService.compressImage(image, quality: .low)
        }

        return try await repository.createAnswer(
            to: reflection,
            questionId: questionId,
            text: trimmed,
            imageData: imageData,
            in: space
        )
    }

    func update(answer: SpaceAnswer, in space: Space, text: String, image: UIImage?) async throws -> SpaceAnswer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpaceError.bodyRequired }
        guard trimmed.count <= Constants.Limits.spaceResponseMaxLength else { throw SpaceError.bodyTooLong }

        var imageData: Data?
        if let image {
            imageData = await imageService.compressImage(image, quality: .low)
        }

        return try await repository.updateAnswer(
            answer,
            text: trimmed,
            imageData: imageData,
            in: space
        )
    }
}
