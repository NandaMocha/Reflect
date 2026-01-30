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
        @State var selectedImage: UIImage? = nil
        @State var selectedVideoURL: URL? = nil
        @State var selectedVideoThumbnail: UIImage? = nil
        @State var selectedVideoDuration: TimeInterval? = nil

        ImagePickerView(
            sourceType: .camera,
            selectedImage: $selectedImage,
            selectedVideoURL: $selectedVideoURL,
            selectedVideoThumbnail: $selectedVideoThumbnail,
            selectedVideoDuration: $selectedVideoDuration
        )
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                processCapturedImage(image)
                showMediaPicker = false
            }
        }
        .onChange(of: selectedVideoURL) { _, newURL in
            if let url = newURL {
                processCapturedVideo(url)
                showMediaPicker = false
            }
        }
    }
}
