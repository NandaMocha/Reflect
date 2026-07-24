import SwiftUI
import OSLog

extension ReflectionEditorView {
    /// Bridges the view's `@State` form fields onto `viewModel`, then delegates to
    /// `viewModel.save()` — which runs the use-case pipeline (CreateReflectionUseCase /
    /// UpdateReflectionUseCase) and, in turn, EvaluateBadgesUseCase. Badge notifications
    /// and celebration state flow back through the VM.
    @MainActor
    func save() async {
        guard isValid else { return }
        isSaving = true

        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTitle : title

        viewModel.title = finalTitle
        viewModel.content = content
        viewModel.selectedLearning = selectedLearning
        viewModel.images = images
        viewModel.videos = videos
        viewModel.voiceRecordings = voiceRecordings
        viewModel.existingImageIds = existingImageIds
        viewModel.existingVideoIds = existingVideoIds
        viewModel.selectedDate = selectedDate
        viewModel.capturedLocation = capturedLocation

        let success = await viewModel.save()
        isSaving = false

        if success {
            if let learning = selectedLearning {
                UserDefaults.standard.setLastUsedLearningId(learning.id)
            }
            NotificationCenter.default.post(name: .reflectionDidSave, object: nil)
            // `.badgesDidUnlock` was posted inside the use case; MainTabView observes it and
            // presents the celebration fullScreenCover. The editor dismisses right away so
            // the celebration lands cleanly over LearningListView.
            onDismiss?()
            dismiss()
        } else {
            os_log("⚠️ [EDITOR] Save failed: %@", log: .default, type: .error, viewModel.errorMessage ?? "unknown")
            errorMessage = viewModel.errorMessage ?? "Failed to save reflection"
            showErrorAlert = true
        }
    }
}
