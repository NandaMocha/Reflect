import SwiftUI
import SwiftData
import PhotosUI
import OSLog
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif

struct ReflectionEditorView: View {
    let mode: ReflectionEditorMode
    var preselectedLearning: Learning?
    var onDismiss: (() -> Void)?

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
    @State var showCreateLearning = false
    @State var showDatePicker = false
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var hasChanges = false
    @State var isSaving = false
    @State var selectedVideoIndex: Int?
    @State var selectedImageIndex: Int?

    // Journaling Suggestions State
    @State var showJournalingPicker = false
    @State var capturedLocation: CapturedLocation?
    @State var showTemplatePicker = false

    // Error handling
    @State var errorMessage: String?
    @State var showErrorAlert = false

    // Celebration state
    @State var showCelebration = false
    @State var celebrationTrigger: BadgeUnlockEvent.CelebrationTrigger = .none

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
        (!content.trimmingCharacters(in: .whitespaces).isEmpty || !images.isEmpty || !videos.isEmpty) || !voiceRecordings.isEmpty &&
        selectedLearning != nil
    }

    var isIOS17_2OrNewer: Bool {
        if #available(iOS 17.2, *) {
            return true
        } else {
            return false
        }
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
                .alert("Error", isPresented: $showErrorAlert) {
                    Button("OK", role: .cancel) {
                        errorMessage = nil
                    }
                } message: {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                    }
                }
                .sheet(isPresented: $showLearningPicker) { learningPickerSheet }
                .sheet(isPresented: $showCreateLearning) { createLearningSheet }
                .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotoItems, maxSelectionCount: Constants.Limits.maxImagesPerReflection - images.count)
                .fullScreenCover(isPresented: $showMediaPicker) {
                    mediaPickerSheet
                }
                .sheet(isPresented: $showDatePicker) { datePickerSheet }
                .sheet(isPresented: $showVoiceRecorder) { voiceRecorderSheet }
                .sheet(isPresented: $showTemplatePicker) { templatePickerSheet }
                #if canImport(JournalingSuggestions)
                .if(isIOS17_2OrNewer) { view in
                    view.journalingSuggestionsPicker(isPresented: $showJournalingPicker) { suggestion in
                        handleJournalingSuggestion(suggestion)
                    }
                }
                #endif
                .sheet(isPresented: Binding(
                    get: { selectedVideoIndex != nil },
                    set: { if !$0 { selectedVideoIndex = nil } }
                )) {
                    videoPlayerSheet
                }
                .fullScreenCover(isPresented: Binding(
                    get: { selectedImageIndex != nil },
                    set: { if !$0 { selectedImageIndex = nil } }
                )) {
                    if let index = selectedImageIndex {
                        EditorImageFullscreenView(images: images, startingIndex: index)
                    }
                }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task { await loadImages(from: newItems) }
                }
                .onAppear {
                    let viewStartTime = CFAbsoluteTimeGetCurrent()
                    os_log("📱 [PERF] ReflectionEditorView onAppear started", log: .default, type: .info)
                    loadExistingData()
                    setupNotificationObservers()
                    os_log("📱 [PERF] ReflectionEditorView onAppear completed in %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - viewStartTime) * 1000)
                }
                .celebration(isPresented: $showCelebration, trigger: celebrationTrigger)
        }
    }
}

#Preview {
    ReflectionEditorView(mode: .create, onDismiss: nil)
        .modelContainer(for: [Learning.self, Reflection.self, ImageAttachment.self, VoiceRecording.self, VideoAttachment.self], inMemory: true)
}
