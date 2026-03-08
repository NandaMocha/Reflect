import Foundation

protocol CreateReflectionUseCaseProtocol {
    func execute(input: CreateReflectionInput) async throws -> Reflection
}

// MARK: - Streak Integration Result

struct CreateReflectionResult {
    let reflection: Reflection
    let streakResult: SubmitStreakReflectionResult?
}

final class CreateReflectionUseCase: CreateReflectionUseCaseProtocol {
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let learningRepository: LearningRepositoryProtocol
    private let imageService: ImageProcessingServiceProtocol
    private let submitStreakUseCase: SubmitStreakReflectionUseCaseProtocol?

    init(
        reflectionRepository: ReflectionRepositoryProtocol,
        learningRepository: LearningRepositoryProtocol,
        imageService: ImageProcessingServiceProtocol,
        submitStreakUseCase: SubmitStreakReflectionUseCaseProtocol? = nil
    ) {
        self.reflectionRepository = reflectionRepository
        self.learningRepository = learningRepository
        self.imageService = imageService
        self.submitStreakUseCase = submitStreakUseCase
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

        // Evaluate streak and badges after creating reflection
        var streakResult: SubmitStreakReflectionResult?
        if let submitStreakUseCase = submitStreakUseCase {
            do {
                streakResult = try await submitStreakUseCase.execute(reflection: reflection)

                // Post notification for UI updates
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .streakDidUpdate,
                        object: nil,
                        userInfo: [
                            "newStreak": streakResult!.newStreak,
                            "unlockedBadges": streakResult!.unlockedBadges,
                            "celebrationTrigger": streakResult!.celebrationTrigger
                        ]
                    )

                    // Post individual badge unlock notifications
                    for badgeID in streakResult!.unlockedBadges {
                        NotificationCenter.default.post(
                            name: .badgeDidUnlock,
                            object: nil,
                            userInfo: [
                                "badgeID": badgeID,
                                "celebrationTrigger": badgeID.celebration
                            ]
                        )
                    }
                }
            } catch {
                // Log error but don't fail the reflection creation
                print("⚠️ Failed to evaluate streak: \(error.localizedDescription)")
            }
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
