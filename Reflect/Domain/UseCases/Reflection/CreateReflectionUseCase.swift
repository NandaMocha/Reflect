import Foundation
import SwiftData
import UIKit

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
        reflection.createdAt = input.createdAt

        if let promptID = input.promptID {
            reflection.promptID = promptID
        }

        if let location = input.capturedLocation {
            reflection.locationLatitude = location.latitude
            reflection.locationLongitude = location.longitude
            reflection.locationName = location.name
        }

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

        for (index, videoInput) in input.videos.enumerated() {
            let thumbnailData = videoInput.thumbnailImage.jpegData(compressionQuality: 0.8)
            let attachment = VideoAttachment(
                videoData: videoInput.videoData,
                thumbnailData: thumbnailData,
                caption: videoInput.caption,
                duration: videoInput.duration
            )
            attachment.sortOrder = index
            reflection.videos.append(attachment)
        }

        for (index, voiceInput) in input.voiceRecordings.enumerated() {
            let recording = VoiceRecording(
                audioData: voiceInput.audioData,
                transcription: voiceInput.transcription,
                language: voiceInput.language,
                duration: voiceInput.duration,
                waveformSamples: voiceInput.waveformSamples,
                sortOrder: index
            )
            reflection.voiceRecordings.append(recording)
        }

        try await reflectionRepository.create(reflection)

        if let evaluateBadgesUseCase = evaluateBadgesUseCase,
           let modelContext = input.modelContext {
            let unlocked = (try? await evaluateBadgesUseCase.execute(
                input: EvaluateBadgesInput(modelContext: modelContext, newReflection: reflection)
            )) ?? []

            if !unlocked.isEmpty {
                NotificationCenter.default.post(name: .badgesDidUnlock, object: unlocked)
            }
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
