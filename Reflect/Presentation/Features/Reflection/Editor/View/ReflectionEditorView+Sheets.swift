import SwiftUI

// MARK: - Sheets & Alerts Extension

extension ReflectionEditorView {
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
        VoiceAudioView(
            mode: .record(onComplete: { recording in
                voiceRecordings.append(recording)
                hasChanges = true
            }, fromWidget: false),
            isPresented: $showVoiceRecorder
        )
    }

    var templatePickerSheet: some View {
        ReflectionTemplateSheet(
            isPresented: $showTemplatePicker,
            onTemplateSelected: { promptID, templateText in
                viewModel.promptID = promptID
                if !content.isEmpty {
                    content += "\n\n"
                }
                content += templateText
                hasChanges = true
            }
        )
    }

    @ViewBuilder
    var mediaPickerSheet: some View {
        ImagePickerView(
            sourceType: .camera,
            onPhotoPicked: { image in
                processCapturedImage(image)
                showMediaPicker = false
            },
            onVideoPicked: { url, thumbnail, duration in
                processCapturedVideo(url)
                showMediaPicker = false
            }
        )
    }

    @ViewBuilder
    var videoPlayerSheet: some View {
        if let index = selectedVideoIndex, index < videos.count {
            VideoPlayerView(videoData: videos[index].videoData)
        } else {
            EmptyView()
        }
    }
}
