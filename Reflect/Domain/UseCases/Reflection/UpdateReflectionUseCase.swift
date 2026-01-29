import Foundation

protocol UpdateReflectionUseCaseProtocol {
    func execute(input: UpdateReflectionInput) async throws -> Reflection
}

final class UpdateReflectionUseCase: UpdateReflectionUseCaseProtocol {
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let learningRepository: LearningRepositoryProtocol
    private let imageService: ImageProcessingServiceProtocol

    init(
        reflectionRepository: ReflectionRepositoryProtocol,
        learningRepository: LearningRepositoryProtocol,
        imageService: ImageProcessingServiceProtocol
    ) {
        self.reflectionRepository = reflectionRepository
        self.learningRepository = learningRepository
        self.imageService = imageService
    }

    func execute(input: UpdateReflectionInput) async throws -> Reflection {
        guard input.isValid else {
            throw ReflectionError.invalidInput("Invalid input")
        }

        guard let reflection = try await reflectionRepository.fetch(id: input.reflectionId) else {
            throw ReflectionError.notFound
        }

        guard let learningId = input.learningId,
              let learning = try await learningRepository.fetch(id: learningId) else {
            throw ReflectionError.learningNotFound
        }

        reflection.title = input.title.trimmingCharacters(in: .whitespaces)
        reflection.plainTextContent = input.content
        reflection.learning = learning

        // Remove images
        reflection.images.removeAll { input.imageIdsToRemove.contains($0.id) }

        // Add new images
        let startIndex = reflection.images.count
        for (index, imageInput) in input.imagesToAdd.enumerated() {
            let imageData = imageService.compressImage(imageInput.image, quality: .high)
            let thumbnailData = imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200))

            let attachment = ImageAttachment(
                imageData: imageData,
                thumbnailData: thumbnailData,
                caption: imageInput.caption,
                sortOrder: startIndex + index
            )
            reflection.images.append(attachment)
        }

        // Remove voice recordings
        reflection.voiceRecordings.removeAll { input.voiceRecordingIdsToRemove.contains($0.id) }

        // Add new voice recordings
        let voiceStartIndex = reflection.voiceRecordings.count
        for (index, voiceInput) in input.voiceRecordingsToAdd.enumerated() {
            let recording = VoiceRecording(
                audioData: voiceInput.audioData,
                transcription: voiceInput.transcription,
                language: voiceInput.language,
                duration: voiceInput.duration,
                sortOrder: voiceStartIndex + index
            )
            reflection.voiceRecordings.append(recording)
        }

        try await reflectionRepository.update(reflection)

        return reflection
    }
}
