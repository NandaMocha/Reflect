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

    /// ViewModel owning the domain save pipeline (CreateReflectionUseCase → EvaluateBadgesUseCase).
    /// The view's @State form fields mirror the VM's fields today; they're copied onto the VM
    /// before `save()` is called. A future refactor can fold the form fields into the VM so
    /// bindings flow through `$viewModel.title` etc. directly — see follow-up in
    /// docs/reviews/achievement-counter-root-cause.md.
    @State var viewModel: ReflectionEditorViewModel

    init(
        mode: ReflectionEditorMode,
        preselectedLearning: Learning? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.preselectedLearning = preselectedLearning
        self.onDismiss = onDismiss
        // DIContainer is configured at app launch (ReflectApp.init) so this is safe.
        self._viewModel = State(initialValue: DIContainer.shared.makeReflectionEditorViewModel(mode: Self.vmMode(from: mode)))
    }

    private static func vmMode(from mode: ReflectionEditorMode) -> ReflectionEditorViewModel.Mode {
        switch mode {
        case .create: return .create
        case .edit(let reflection): return .edit(reflection)
        }
    }

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
        let hasContent = !content.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMedia = !images.isEmpty || !videos.isEmpty || !voiceRecordings.isEmpty
        return (hasContent || hasMedia) && selectedLearning != nil
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
                .celebration(
                    isPresented: Binding(
                        get: { viewModel.showCelebration },
                        set: { viewModel.showCelebration = $0 }
                    ),
                    trigger: viewModel.celebrationTrigger
                )
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Learning.self, Reflection.self, ImageAttachment.self,
            VoiceRecording.self, VideoAttachment.self, Badge.self, MonthlyAchievement.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    DIContainer.shared.configure(with: container.mainContext)
    return ReflectionEditorView(mode: .create, onDismiss: nil)
        .modelContainer(container)
}
