import SwiftUI
import SwiftData

// MARK: - Save Logic Extension

extension ReflectionEditorView {
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

        let imageService = ImageProcessingService.shared
        for (index, imageInput) in images.enumerated() {
            if let imageData = imageService.compressImage(imageInput.image, quality: CompressionQuality.high),
               let thumbnailData = imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200)) {
                let attachment = ImageAttachment(
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    caption: imageInput.caption
                )
                attachment.sortOrder = index
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

        let imageService = ImageProcessingService.shared

        let currentImageIds = Set(images.map { $0.id })

        let imagesToRemove = reflection.images.filter { !currentImageIds.contains($0.id) }
        for image in imagesToRemove {
            modelContext.delete(image)
            if let index = reflection.images.firstIndex(where: { $0.id == image.id }) {
                reflection.images.remove(at: index)
            }
        }

        for (index, imageInput) in images.enumerated() {
            if existingImageIds.contains(imageInput.id),
               let existingImage = reflection.images.first(where: { $0.id == imageInput.id }) {
                existingImage.sortOrder = index
                existingImage.caption = imageInput.caption
            } else {
                if let imageData = imageService.compressImage(imageInput.image, quality: .high),
                   let thumbnailData = imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200)) {
                    let newImage = ImageAttachment(
                        imageData: imageData,
                        thumbnailData: thumbnailData,
                        caption: imageInput.caption
                    )
                    newImage.sortOrder = index
                    reflection.images.append(newImage)
                }
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
}
