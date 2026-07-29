import Foundation
import UIKit

protocol CreateSpaceReflectionUseCaseProtocol {
    func execute(in space: Space, title: String, promptText: String, image: UIImage?) async throws -> SpaceReflection
}

/// Validates a reflection's title (1...max) and prompt (non-empty) before creating it.
/// An attached image is compressed hard (`.low`: max 800px, JPEG 0.3) before upload so
/// shared-space payloads stay small.
@MainActor
final class CreateSpaceReflectionUseCase: CreateSpaceReflectionUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol
    private let imageService: ImageProcessingServiceProtocol

    init(repository: SpaceRepositoryProtocol, imageService: ImageProcessingServiceProtocol) {
        self.repository = repository
        self.imageService = imageService
    }

    func execute(in space: Space, title: String, promptText: String, image: UIImage?) async throws -> SpaceReflection {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw SpaceError.titleRequired }
        guard trimmedTitle.count <= Constants.Limits.spaceReflectionTitleMaxLength else { throw SpaceError.titleTooLong }

        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { throw SpaceError.promptRequired }
        guard trimmedPrompt.count <= Constants.Limits.spaceReflectionPromptMaxLength else { throw SpaceError.promptTooLong }

        var imageData: Data?
        if let image {
            imageData = await imageService.compressImage(image, quality: .low)
        }

        return try await repository.createReflection(in: space, title: trimmedTitle, promptText: trimmedPrompt, imageData: imageData)
    }
}
