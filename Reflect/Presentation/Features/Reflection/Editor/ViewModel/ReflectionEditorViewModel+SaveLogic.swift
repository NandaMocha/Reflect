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
            let newlyUnlockedBadges: [BadgeID]
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
                let (_, unlocked) = try await createUseCase.execute(input: input)
                newlyUnlockedBadges = unlocked

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
                let (_, unlocked) = try await updateUseCase.execute(input: input)
                newlyUnlockedBadges = unlocked
            }

            // Drive celebration from the use-case result synchronously so the view sees
            // showCelebration=true before it reads .showCelebration to decide whether to
            // defer dismissal. Relying on the async .badgesDidUnlock observer was unreliable
            // because SwiftUI's dismiss would fire before the observer's main-queue block.
            if !newlyUnlockedBadges.isEmpty,
               let headline = Self.headlineBadge(from: newlyUnlockedBadges) {
                unlockedBadges = newlyUnlockedBadges
                celebrationTrigger = headline.celebration
                showCelebration = true
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
