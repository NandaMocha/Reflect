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
            onPhotoPicked: { image in
                print("[Sheets] onPhotoPicked called")
                processCapturedImage(image)
                showMediaPicker = false
            },
            onVideoPicked: { url, thumbnail, duration in
                print("[Sheets] onVideoPicked called - URL: \(url), duration: \(duration)")
                processCapturedVideo(url)
                showMediaPicker = false
            }
        )
        .onAppear {
            print("[Sheets] mediaPickerSheet appeared")
        }
    }
}
