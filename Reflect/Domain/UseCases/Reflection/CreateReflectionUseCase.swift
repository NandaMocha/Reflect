import Foundation
import SwiftData

protocol CreateReflectionUseCaseProtocol {
    func execute(input: CreateReflectionInput) async throws -> Reflection
}

final class CreateReflectionUseCase: CreateReflectionUseCaseProtocol {
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let learningRepository: LearningRepositoryProtocol
    private let imageService: ImageProcessingServiceProtocol
    private let evaluateBadgesUseCase: EvaluateBadgesUseCaseProtocol?

    init(
        reflectionRepository: ReflectionRepositoryProtocol,
        learningRepository: LearningRepositoryProtocol,
        imageService: ImageProcessingServiceProtocol,
        evaluateBadgesUseCase: EvaluateBadgesUseCaseProtocol? = nil
    ) {
        self.reflectionRepository = reflectionRepository
        self.learningRepository = learningRepository
        self.imageService = imageService
        self.evaluateBadgesUseCase = evaluateBadgesUseCase
    }

    func execute(input: CreateReflectionInput) async throws -> Reflection {
        guard input.isValid else {
            throw ReflectionError.invalidInput(input.validationErrors.first ?? "Invalid input")
        }

        guard let learningId = input.learningId,
              let learning = try await learningRepository.fetch(id: learningId) else {
            throw ReflectionError.learningNotFound
        }

        let reflection = Reflection(
            title: input.title.trimmingCharacters(in: .whitespaces),
            plainTextContent: input.content
        )
        reflection.learning = learning

        // Store prompt ID if provided
        if let promptID = input.promptID {
            reflection.promptID = promptID
        }

        // Process images (async)
        for (index, imageInput) in input.images.enumerated() {
            let imageData = await imageService.compressImage(imageInput.image, quality: .high)
            let thumbnailData = await imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200))

            let attachment = ImageAttachment(
                imageData: imageData,
                thumbnailData: thumbnailData,
                caption: imageInput.caption,
                sortOrder: index
            )
            reflection.images.append(attachment)
        }

        // Process voice recordings
        for (index, voiceInput) in input.voiceRecordings.enumerated() {
            let recording = VoiceRecording(
                audioData: voiceInput.audioData,
                transcription: voiceInput.transcription,
                language: voiceInput.language,
                duration: voiceInput.duration,
                sortOrder: index
            )
            reflection.voiceRecordings.append(recording)
        }

        try await reflectionRepository.create(reflection)

        // Evaluate badges after reflection is created
        if let evaluateBadgesUseCase = evaluateBadgesUseCase,
           let modelContext = input.modelContext {
            let newlyUnlockedBadges = try? await evaluateBadgesUseCase.execute(
                input: EvaluateBadgesInput(modelContext: modelContext, newReflection: reflection)
            )

            // Post notification for newly unlocked badges
            if let unlockedBadges = newlyUnlockedBadges, !unlockedBadges.isEmpty {
                NotificationCenter.default.post(
                    name: .badgesDidUnlock,
                    object: unlockedBadges
                )
            }

            // Post notification for progress update
            NotificationCenter.default.post(name: .badgeProgressDidUpdate, object: nil)
        }

        return reflection
    }
}

enum ReflectionError: Error, LocalizedError {
    case invalidInput(String)
    case learningNotFound
    case notFound
    case titleRequired
    case contentRequired

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .learningNotFound:
            return "Learning not found"
        case .notFound:
            return "Reflection not found"
        case .titleRequired:
            return "Title is required"
        case .contentRequired:
            return "Content is required"
        }
    }
}
