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

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedContent = content.trimmingCharacters(in: .whitespaces)

        do {
            switch mode {
            case .create:
                let input = CreateReflectionInput(
                    title: trimmedTitle,
                    content: trimmedContent,
                    learningId: selectedLearning?.id,
                    promptID: promptID,
                    images: images,
                    videos: videos,
                    voiceRecordings: voiceRecordings,
                    createdAt: selectedDate,
                    capturedLocation: capturedLocation,
                    modelContext: modelContext
                )
                _ = try await createUseCase.execute(input: input)

            case .edit(let reflection):
                let input = UpdateReflectionInput(
                    reflectionId: reflection.id,
                    title: trimmedTitle,
                    content: trimmedContent,
                    learningId: selectedLearning?.id,
                    createdAt: selectedDate,
                    capturedLocation: capturedLocation,
                    images: images,
                    existingImageIds: existingImageIds,
                    videos: videos,
                    existingVideoIds: existingVideoIds,
                    voiceRecordings: voiceRecordings,
                    modelContext: modelContext
                )
                _ = try await updateUseCase.execute(input: input)
            }

            // The use case already posted `.badgesDidUnlock` for any crossed thresholds.
            // MainTabView observes that notification and presents CelebrationView as a
            // fullScreenCover, independently of this view model's lifecycle.

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
