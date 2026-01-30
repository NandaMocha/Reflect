import SwiftUI

// MARK: - Sheets & Alerts Extension

extension ReflectionEditorView {
    var learningPickerSheet: some View {
        LearningPickerSheet(
            selectedLearning: $selectedLearning,
            learnings: learnings,
            onDismiss: {
                hasChanges = true
                showLearningPicker = false
            }
        )
    }

    var datePickerSheet: some View {
        DatePickerSheet(
            selectedDate: $selectedDate,
            onDismiss: {
                hasChanges = true
                showDatePicker = false
            }
        )
    }

    var voiceRecorderSheet: some View {
        VoiceRecorderView(isPresented: $showVoiceRecorder) { recording in
            voiceRecordings.append(recording)
            hasChanges = true
        }
    }

    @ViewBuilder
    var mediaPickerSheet: some View {
        CustomCameraView(
            mediaResult: Binding(
                get: { nil },
                set: { result in
                    if let result = result {
                        handleCameraResult(result)
                    }
                }
            ),
            isPresented: $showMediaPicker
        )
    }

    private func handleCameraResult(_ result: CameraMediaResult) {
        if result.isPhoto, let image = result.image {
            processCapturedImage(image)
        } else if result.isVideo, let url = result.videoURL {
            processCapturedVideo(url)
        }
    }
}
