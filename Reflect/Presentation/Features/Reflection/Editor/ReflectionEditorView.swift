import SwiftUI
import SwiftData
import PhotosUI

struct ReflectionEditorView: View {
    let mode: ReflectionEditorMode
    var preselectedLearning: Learning?

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Learning.sortOrder) var learnings: [Learning]

    // Form State
    @State var title = ""
    @State var content = ""
    @State var selectedLearning: Learning?
    @State var images: [ImageInput] = []
    @State var videos: [VideoInput] = []
    @State var existingImageIds: Set<UUID> = []
    @State var existingVideoIds: Set<UUID> = []
    @State var voiceRecordings: [VoiceRecordingInput] = []
    @State var selectedDate = Date()

    // UI State
    @State var showDiscardAlert = false
    @State var showImagePicker = false
    @State var showMediaPicker = false
    @State var showVoiceRecorder = false
    @State var showLearningPicker = false
    @State var showDatePicker = false
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var hasChanges = false
    @State var isSaving = false

    @FocusState var focusedField: ReflectionEditorField?

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var navigationTitle: String {
        isEditing ? "Edit Reflection" : "New Reflection"
    }

    var defaultTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d"
        return "Reflection on \(formatter.string(from: selectedDate))"
    }

    var isValid: Bool {
        // Title is not mandatory - uses default value if empty
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedLearning != nil
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .confirmationAlert(
                    title: "Discard Changes?",
                    message: "You have unsaved changes. Are you sure you want to discard them?",
                    isPresented: $showDiscardAlert,
                    confirmButtonTitle: "Discard",
                    cancelButtonTitle: "Keep Editing",
                    isDestructive: true
                ) {
                    dismiss()
                }
                .sheet(isPresented: $showLearningPicker) { learningPickerSheet }
                .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotoItems, maxSelectionCount: Constants.Limits.maxImagesPerReflection - images.count)
                .sheet(isPresented: $showMediaPicker) {
                    MediaSourcePicker(
                        selectedImage: Binding(
                            get: { nil },
                            set: { newImage in
                                if let image = newImage {
                                    processCapturedImage(image)
                                }
                            }
                        ),
                        selectedVideoURL: Binding(
                            get: { nil },
                            set: { newVideoURL in
                                if let videoURL = newVideoURL {
                                    processCapturedVideo(videoURL)
                                }
                            }
                        ),
                        isPresented: $showMediaPicker
                    )
                }
                .sheet(isPresented: $showDatePicker) { datePickerSheet }
                .sheet(isPresented: $showVoiceRecorder) { voiceRecorderSheet }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task { await loadImages(from: newItems) }
                }
                .onAppear { loadExistingData() }
        }
    }
}

#Preview {
    ReflectionEditorView(mode: .create)
        .modelContainer(for: [Learning.self, Reflection.self, ImageAttachment.self, VoiceRecording.self, VideoAttachment.self], inMemory: true)
}
