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
        ImagePickerView(
            sourceType: .camera,
            selectedImage: $cameraSelectedImage,
            selectedVideoURL: $cameraSelectedVideoURL,
            selectedVideoThumbnail: $cameraSelectedVideoThumbnail,
            selectedVideoDuration: $cameraSelectedVideoDuration
        )
        .onChange(of: cameraSelectedImage) { _, newImage in
            if let image = newImage {
                processCapturedImage(image)
                showMediaPicker = false
                cameraSelectedImage = nil
            }
        }
        .onChange(of: cameraSelectedVideoURL) { _, newURL in
            if let url = newURL {
                processCapturedVideo(url)
                showMediaPicker = false
                cameraSelectedVideoURL = nil
            }
        }
    }
}
