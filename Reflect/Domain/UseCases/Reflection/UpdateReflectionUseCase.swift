import Foundation

protocol UpdateReflectionUseCaseProtocol {
    func execute(input: UpdateReflectionInput) async throws -> Reflection
}

final class UpdateReflectionUseCase: UpdateReflectionUseCaseProtocol {
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
        reflection.createdAt = input.createdAt
        reflection.updatedAt = Date()

        if let location = input.capturedLocation {
            reflection.locationLatitude = location.latitude
            reflection.locationLongitude = location.longitude
            reflection.locationName = location.name
        } else {
            reflection.locationLatitude = nil
            reflection.locationLongitude = nil
            reflection.locationName = nil
        }

        try await reconcileImages(reflection: reflection, desired: input.images, existingIds: input.existingImageIds)
        reconcileVideos(reflection: reflection, desired: input.videos, existingIds: input.existingVideoIds)
        reconcileVoiceRecordings(reflection: reflection, desired: input.voiceRecordings)

        try await reflectionRepository.update(reflection)

        if let evaluateBadgesUseCase = evaluateBadgesUseCase,
           let modelContext = input.modelContext {
            let newlyUnlockedBadges = try? await evaluateBadgesUseCase.execute(
                input: EvaluateBadgesInput(modelContext: modelContext, newReflection: reflection)
            )

            if let unlockedBadges = newlyUnlockedBadges, !unlockedBadges.isEmpty {
                NotificationCenter.default.post(name: .badgesDidUnlock, object: unlockedBadges)
            }

            NotificationCenter.default.post(name: .badgeProgressDidUpdate, object: nil)
        }

        return reflection
    }

    // MARK: - Reconciliation helpers

    private func reconcileImages(
        reflection: Reflection,
        desired: [ImageInput],
        existingIds: Set<UUID>
    ) async throws {
        let desiredIds = Set(desired.map { $0.id })
        let toDelete = reflection.images.filter { !desiredIds.contains($0.id) }
        for attachment in toDelete {
            if let idx = reflection.images.firstIndex(where: { $0.id == attachment.id }) {
                reflection.images.remove(at: idx)
            }
        }

        for (index, input) in desired.enumerated() {
            if existingIds.contains(input.id),
               let existing = reflection.images.first(where: { $0.id == input.id }) {
                existing.sortOrder = index
                existing.caption = input.caption
            } else {
                let imageData = await imageService.compressImage(input.image, quality: .high)
                let thumbnailData = await imageService.generateThumbnail(input.image, size: CGSize(width: 200, height: 200))
                let attachment = ImageAttachment(
                    id: input.id,
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    caption: input.caption,
                    sortOrder: index
                )
                reflection.images.append(attachment)
            }
        }
    }

    private func reconcileVideos(
        reflection: Reflection,
        desired: [VideoInput],
        existingIds: Set<UUID>
    ) {
        let desiredIds = Set(desired.map { $0.id })
        let toDelete = reflection.videos.filter { !desiredIds.contains($0.id) }
        for attachment in toDelete {
            if let idx = reflection.videos.firstIndex(where: { $0.id == attachment.id }) {
                reflection.videos.remove(at: idx)
            }
        }

        for (index, input) in desired.enumerated() {
            if existingIds.contains(input.id),
               let existing = reflection.videos.first(where: { $0.id == input.id }) {
                existing.sortOrder = index
                existing.caption = input.caption
            } else {
                let thumbnailData = input.thumbnailImage.jpegData(compressionQuality: 0.8)
                let attachment = VideoAttachment(
                    id: input.id,
                    videoData: input.videoData,
                    thumbnailData: thumbnailData,
                    caption: input.caption,
                    duration: input.duration,
                    sortOrder: index
                )
                reflection.videos.append(attachment)
            }
        }
    }

    private func reconcileVoiceRecordings(
        reflection: Reflection,
        desired: [VoiceRecordingInput]
    ) {
        let keptIds = Set(desired.compactMap { $0.existingId })
        let toDelete = reflection.voiceRecordings.filter { !keptIds.contains($0.id) }
        for recording in toDelete {
            if let idx = reflection.voiceRecordings.firstIndex(where: { $0.id == recording.id }) {
                reflection.voiceRecordings.remove(at: idx)
            }
        }

        for (index, input) in desired.enumerated() {
            if let existingId = input.existingId,
               let existing = reflection.voiceRecordings.first(where: { $0.id == existingId }) {
                existing.sortOrder = index
            } else {
                let recording = VoiceRecording(
                    audioData: input.audioData,
                    transcription: input.transcription,
                    language: input.language,
                    duration: input.duration,
                    sortOrder: index
                )
                reflection.voiceRecordings.append(recording)
            }
        }
    }
}
