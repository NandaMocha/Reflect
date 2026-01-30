import Foundation

// MARK: - Save Action

extension ReflectionEditorViewModel {
    @MainActor
    func save() async -> Bool {
        guard isValid else {
            errorMessage = validationErrors.first
            HapticManager.shared.error()
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            switch mode {
            case .create:
                let input = CreateReflectionInput(
                    title: title.trimmingCharacters(in: .whitespaces),
                    content: content.trimmingCharacters(in: .whitespaces),
                    learningId: selectedLearning?.id,
                    images: images,
                    voiceRecordings: voiceRecordings
                )
                try await createUseCase.execute(input: input)

            case .edit(let reflection):
                let newImages = images.filter { !existingImageIds.contains($0.id) }
                let removedImageIds = reflection.images
                    .filter { !images.map { $0.id }.contains($0.id) }
                    .map { $0.id }

                let newVideos = videos.filter { !existingVideoIds.contains($0.id) }
                let removedVideoIds = reflection.videos
                    .filter { !videos.map { $0.id }.contains($0.id) }
                    .map { $0.id }

                let newRecordings = voiceRecordings.filter { $0.existingId == nil }
                let removedRecordingIds = reflection.voiceRecordings
                    .filter { !voiceRecordings.compactMap { $0.existingId }.contains($0.id) }
                    .map { $0.id }

                let input = UpdateReflectionInput(
                    reflectionId: reflection.id,
                    title: title.trimmingCharacters(in: .whitespaces),
                    content: content.trimmingCharacters(in: .whitespaces),
                    learningId: selectedLearning?.id,
                    imagesToAdd: newImages,
                    imageIdsToRemove: removedImageIds,
                    videosToAdd: newVideos,
                    videoIdsToRemove: removedVideoIds,
                    voiceRecordingsToAdd: newRecordings,
                    voiceRecordingIdsToRemove: removedRecordingIds
                )
                try await updateUseCase.execute(input: input)
            }

            isLoading = false
            HapticManager.shared.success()
            return true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }
}
