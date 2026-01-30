import SwiftUI
import SwiftData

// MARK: - Save Logic Extension

extension ReflectionEditorView {
    // MARK: - Types for Concurrent Image Processing

    private struct ProcessedImageResult {
        let index: Int
        let imageData: Data?
        let thumbnailData: Data?
        let caption: String?
    }

    @MainActor
    func save() async {
        guard isValid else { return }
        isSaving = true

        do {
            switch mode {
            case .create:
                try await createReflection()
            case .edit(let reflection):
                try await updateReflection(reflection)
            }

            HapticManager.shared.success()
            dismiss()
        } catch {
            HapticManager.shared.error()
        }

        isSaving = false
    }

    func createReflection() async throws {
        // Use default title if empty
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTitle : title.trimmingCharacters(in: .whitespaces)

        let reflection = Reflection(
            title: finalTitle,
            plainTextContent: content.trimmingCharacters(in: .whitespaces)
        )
        reflection.learning = selectedLearning
        reflection.createdAt = selectedDate

        // Process images concurrently for better performance
        let imageResults = await processImagesConcurrently(images)

        for result in imageResults {
            if let imageData = result.imageData, let thumbnailData = result.thumbnailData {
                let attachment = ImageAttachment(
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    caption: result.caption
                )
                attachment.sortOrder = result.index
                reflection.images.append(attachment)
            }
        }

        for (index, voiceInput) in voiceRecordings.enumerated() {
            let recording = VoiceRecording(
                audioData: voiceInput.audioData,
                transcription: voiceInput.transcription,
                language: voiceInput.language,
                duration: voiceInput.duration
            )
            recording.sortOrder = index
            reflection.voiceRecordings.append(recording)
        }

        modelContext.insert(reflection)
        try modelContext.save()
    }

    func updateReflection(_ reflection: Reflection) async throws {
        // Use default title if empty
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTitle : title.trimmingCharacters(in: .whitespaces)

        reflection.title = finalTitle
        reflection.plainTextContent = content.trimmingCharacters(in: .whitespaces)
        reflection.learning = selectedLearning
        reflection.createdAt = selectedDate
        reflection.updatedAt = Date()

        let currentImageIds = Set(images.map { $0.id })

        let imagesToRemove = reflection.images.filter { !currentImageIds.contains($0.id) }
        for image in imagesToRemove {
            modelContext.delete(image)
            if let index = reflection.images.firstIndex(where: { $0.id == image.id }) {
                reflection.images.remove(at: index)
            }
        }

        // Collect new images that need processing
        let newImages = images.filter { !existingImageIds.contains($0.id) }

        // Process new images concurrently
        let imageResults = await processImagesConcurrently(newImages)

        for result in imageResults {
            if let imageData = result.imageData, let thumbnailData = result.thumbnailData {
                let newImage = ImageAttachment(
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    caption: result.caption
                )
                newImage.sortOrder = result.index
                reflection.images.append(newImage)
            }
        }

        // Update existing images (no processing needed)
        for (index, imageInput) in images.enumerated() {
            if existingImageIds.contains(imageInput.id),
               let existingImage = reflection.images.first(where: { $0.id == imageInput.id }) {
                existingImage.sortOrder = index
                existingImage.caption = imageInput.caption
            }
        }

        let existingIdsToKeep = Set(voiceRecordings.compactMap { $0.existingId })

        let recordingsToRemove = reflection.voiceRecordings.filter { !existingIdsToKeep.contains($0.id) }
        for recording in recordingsToRemove {
            modelContext.delete(recording)
            if let index = reflection.voiceRecordings.firstIndex(where: { $0.id == recording.id }) {
                reflection.voiceRecordings.remove(at: index)
            }
        }

        for (index, input) in voiceRecordings.enumerated() {
            if let existingId = input.existingId,
               let existingRecording = reflection.voiceRecordings.first(where: { $0.id == existingId }) {
                existingRecording.sortOrder = index
            } else {
                let newRecording = VoiceRecording(
                    audioData: input.audioData,
                    transcription: input.transcription,
                    language: input.language,
                    duration: input.duration
                )
                newRecording.sortOrder = index
                reflection.voiceRecordings.append(newRecording)
            }
        }

        try modelContext.save()
    }

    // MARK: - Concurrent Image Processing

    private func processImagesConcurrently(_ images: [ImageInput]) async -> [ProcessedImageResult] {
        let imageService = ImageProcessingService.shared

        // Process images concurrently using TaskGroup
        return await withThrowingTaskGroup(of: ProcessedImageResult.self) { group in
            for (index, imageInput) in images.enumerated() {
                group.addTask {
                    let imageData = await imageService.compressImage(imageInput.image, quality: CompressionQuality.high)
                    let thumbnailData = await imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200))

                    return ProcessedImageResult(
                        index: index,
                        imageData: imageData,
                        thumbnailData: thumbnailData,
                        caption: imageInput.caption
                    )
                }
            }

            var results: [ProcessedImageResult] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.index < $1.index }
        }
    }
}
