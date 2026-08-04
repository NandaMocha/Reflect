import Foundation
import UIKit

protocol CreateSpaceReflectionUseCaseProtocol {
    func execute(in space: Space, title: String, note: String?, questions: [SpaceQuestion], image: UIImage?) async throws -> SpaceReflection
}

/// Validates a reflection's title (1...max), note (optional, ≤max), and questions (1-5,
/// non-empty) before creating it. An attached image is compressed hard (`.low`: max 800px,
/// JPEG 0.3) before upload so shared-space payloads stay small.
@MainActor
final class CreateSpaceReflectionUseCase: CreateSpaceReflectionUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol
    private let imageService: ImageProcessingServiceProtocol

    init(repository: SpaceRepositoryProtocol, imageService: ImageProcessingServiceProtocol) {
        self.repository = repository
        self.imageService = imageService
    }

    func execute(in space: Space, title: String, note: String?, questions: [SpaceQuestion], image: UIImage?) async throws -> SpaceReflection {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw SpaceError.titleRequired }
        guard trimmedTitle.count <= Constants.Limits.spaceReflectionTitleMaxLength else { throw SpaceError.titleTooLong }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNote {
            guard trimmedNote.count <= Constants.Limits.spaceReflectionNoteMaxLength else { throw SpaceError.noteTooLong }
        }

        try SpaceQuestion.validate(questions)

        var imageData: Data?
        if let image {
            imageData = await imageService.compressImage(image, quality: .low)
        }

        return try await repository.createReflection(
            in: space,
            title: trimmedTitle,
            note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote,
            questions: questions,
            imageData: imageData
        )
    }
}
