import SwiftUI
import SwiftData
import AVFoundation

struct ReflectionListView: View {
    // Optional learning to filter reflections - nil means show all reflections
    var learning: Learning?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Learning.sortOrder) private var learnings: [Learning]

    // ViewModel - handles data loading, filtering, sorting, grouping
    @State private var viewModel: ReflectionListViewModel?

    // Quick action states
    @State private var showActionMenu = false
    @State private var showCameraPicker = false
    @State private var showVoiceRecorder = false
    @State private var showNoLearningAlert = false
    @State private var showEditor = false
    @State private var reflectionToMove: Reflection?

    // Widget action handling
    @Binding var widgetAction: WidgetAction?

    @Namespace private var menuNamespace

    init(learning: Learning? = nil, widgetAction: Binding<WidgetAction?> = .constant(nil)) {
        self.learning = learning
        self._widgetAction = widgetAction
    }

    /// Show the search field only when there's data, or the user has an active search /
    /// favorites filter (so a zero-result search can still be cleared). Hidden on the
    /// genuinely-empty state (learning with no reflections yet).
    private var searchFieldActive: Bool {
        guard let vm = viewModel else { return false }
        return !vm.isEmpty || !vm.searchQuery.isEmpty || vm.showFavoritesOnly
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let viewModel = viewModel {
                    if viewModel.isLoading && viewModel.reflections.isEmpty {
                        loadingView
                    } else if viewModel.isEmpty {
                        emptyState
                    } else if viewModel.reflections.isEmpty {
                        noResultsState
                    } else {
                        reflectionList
                    }
                } else {
                    loadingView
                }
            }

            // FAB with quick actions
            if let viewModel = viewModel, !viewModel.isEmpty {
                quickActionMenu
                    .padding(Constants.Spacing.lg)
            }
        }
        .navigationTitle("\(learning?.title ?? "") Reflections")
        .searchable(
            text: Binding(
                get: { viewModel?.searchQuery ?? "" },
                set: { newValue in viewModel?.updateSearchQuery(newValue) }
            ),
            prompt: "Search reflections...",
            isActive: searchFieldActive
        )
        .cameraReflectionFlow(
            isPresented: $showCameraPicker,
            onPhotoPicked: { image in
                Task { await handlePhotoPicked(image) }
            },
            onVideoPicked: { url, thumbnail, duration in
                Task { await handleVideoPicked(url: url, thumbnail: thumbnail, duration: duration) }
            }
        )
        .fullScreenCover(isPresented: $showEditor) {
            ReflectionEditorView(mode: .create, preselectedLearning: learning, onDismiss: {
                showEditor = false
                Task {
                    await viewModel?.loadReflections()
                }
            })
        }
        .sheet(isPresented: $showVoiceRecorder) {
            voiceRecorderSheet
        }
        .sheet(item: $reflectionToMove) { reflection in
            LearningPickerSheet(
                title: "Move to Learning",
                learnings: learnings.filter { $0.id != reflection.learning?.id },
                currentSelection: nil,
                onSelect: { target in
                    Task {
                        await viewModel?.moveReflection(reflection, to: target)
                    }
                }
            )
        }
        .alert("No Learning", isPresented: $showNoLearningAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please create a Learning first before adding reflections")
        }
        .errorAlert(
            Binding(get: { viewModel?.errorMessage }, set: { viewModel?.errorMessage = $0 }),
            title: "Error"
        )
        .onAppear {
            // Initialize ViewModel with proper modelContext
            if viewModel == nil {
                viewModel = ReflectionListViewModel(
                    modelContext: modelContext,
                    learning: learning
                )
            }
            Task {
                await viewModel?.loadReflections()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reflectionDidSave)) { _ in
            // Reload reflections when a notification is received after saving
            Task {
                await viewModel?.loadReflections()
            }
        }
        .onChange(of: widgetAction) { _, action in
            handleWidgetAction(action)
        }
        .navigationDestination(for: Reflection.self) { reflection in
            ReflectionDetailView(reflection: reflection)
        }
    }

    // MARK: - Widget Action Handling

    private func handleWidgetAction(_ action: WidgetAction?) {
        guard let action = action else { return }

        // Validate a learning exists
        guard let _ = getLearningForQuickReflection() else {
            showNoLearningAlert = true
            widgetAction = nil
            return
        }

        switch action {
        case .write:
            showEditor = true
        case .camera:
            showCameraPicker = true
        case .voice:
            showVoiceRecorder = true
        case .insight:
            break
        }

        // Reset action after triggering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            widgetAction = nil
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Constants.Spacing.lg) {
            ProgressView()
            Text("Loading reflections...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Quick Action Menu

    private var quickActionMenu: some View {
        FloatingActionMenu(
            isExpanded: $showActionMenu,
            onTap: {
                // Regular tap - navigate to editor
                showEditor = true
            },
            onCameraTap: {
                // Validate Learning exists before opening camera
                guard let _ = getLearningForQuickReflection() else {
                    showNoLearningAlert = true
                    return
                }
                showCameraPicker = true
            },
            onVoiceTap: {
                // Validate Learning exists before opening voice recorder
                guard let _ = getLearningForQuickReflection() else {
                    showNoLearningAlert = true
                    return
                }
                showVoiceRecorder = true
            }
        )
    }

    // MARK: - Voice Recorder Sheet

    private var voiceRecorderSheet: some View {
        VoiceAudioView(
            mode: .record(onComplete: { recording in
                Task { await handleVoiceRecording(recording) }
            }, fromWidget: widgetAction == .voice),
            isPresented: $showVoiceRecorder
        )
    }

    // MARK: - Handlers

    @MainActor
    private func handlePhotoPicked(_ image: UIImage) async {
        guard let learning = getLearningForQuickReflection() else {
            showNoLearningAlert = true
            return
        }

        let imageService = ImageProcessingService.shared

        // Generate default title
        let title = generateDefaultTitle()

        // Create reflection
        let reflection = Reflection(
            title: title,
            plainTextContent: ""
        )
        reflection.learning = learning
        reflection.createdAt = Date()

        // Process image
        let imageData = await imageService.compressImage(image, quality: .high)
        let thumbnailData = await imageService.generateThumbnail(image, size: CGSize(width: 200, height: 200))

        guard let compressedData = imageData, let thumbData = thumbnailData else {
            viewModel?.quickReflectionError = "Failed to process image"
            return
        }

        let attachment = ImageAttachment(
            imageData: compressedData,
            thumbnailData: thumbData,
            caption: nil
        )
        attachment.sortOrder = 0
        reflection.images.append(attachment)

        // Save
        modelContext.insert(reflection)
        try? modelContext.save()

        // Post notification to refresh reflection list
        NotificationCenter.default.post(name: .reflectionDidSave, object: nil)

        // Reload reflections
        await viewModel?.loadReflections()

        // Track last used learning
        UserDefaults.standard.setLastUsedLearningId(learning.id)

        HapticManager.shared.success()
    }

    @MainActor
    private func handleVideoPicked(url: URL, thumbnail: UIImage, duration: TimeInterval) async {
        guard let learning = getLearningForQuickReflection() else {
            showNoLearningAlert = true
            return
        }

        // Generate default title
        let title = generateDefaultTitle()

        // Create reflection
        let reflection = Reflection(
            title: title,
            plainTextContent: ""
        )
        reflection.learning = learning
        reflection.createdAt = Date()

        // Load video data
        guard let videoData = try? Data(contentsOf: url) else {
            viewModel?.quickReflectionError = "Failed to load video"
            return
        }

        // Generate thumbnail as JPEG
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            viewModel?.quickReflectionError = "Failed to process thumbnail"
            return
        }

        let attachment = VideoAttachment(
            videoData: videoData,
            thumbnailData: thumbnailData,
            caption: nil,
            duration: duration
        )
        attachment.sortOrder = 0
        reflection.videos.append(attachment)

        // Save
        modelContext.insert(reflection)
        try? modelContext.save()

        // Post notification to refresh reflection list
        NotificationCenter.default.post(name: .reflectionDidSave, object: nil)

        // Reload reflections
        await viewModel?.loadReflections()

        // Track last used learning
        UserDefaults.standard.setLastUsedLearningId(learning.id)

        HapticManager.shared.success()
    }

    @MainActor
    private func handleVoiceRecording(_ recording: VoiceRecordingInput) async {
        guard let learning = getLearningForQuickReflection() else {
            showNoLearningAlert = true
            return
        }

        // Use transcription as content, or default text
        let content = recording.transcription ?? "Voice note"

        // Generate default title
        let title = generateDefaultTitle()

        // Create reflection
        let reflection = Reflection(
            title: title,
            plainTextContent: content
        )
        reflection.learning = learning
        reflection.createdAt = Date()

        // Create voice recording attachment
        let voiceRecording = VoiceRecording(
            audioData: recording.audioData,
            transcription: recording.transcription,
            language: recording.language,
            duration: recording.duration,
            waveformSamples: recording.waveformSamples
        )
        voiceRecording.sortOrder = 0
        reflection.voiceRecordings.append(voiceRecording)

        // Save
        modelContext.insert(reflection)
        try? modelContext.save()

        // Post notification to refresh reflection list
        NotificationCenter.default.post(name: .reflectionDidSave, object: nil)

        // Reload reflections
        await viewModel?.loadReflections()

        // Track last used learning
        UserDefaults.standard.setLastUsedLearningId(learning.id)

        HapticManager.shared.success()
    }

    // MARK: - Helper Methods

    private func getLearningForQuickReflection() -> Learning? {
        // Use the view's learning if specified
        if let learning = learning {
            return learning
        }

        // Otherwise try last used first
        if let lastUsedId = UserDefaults.standard.lastUsedLearningId(),
           let lastUsed = learnings.first(where: { $0.id == lastUsedId }) {
            return lastUsed
        }

        // Fall back to first Learning by sortOrder
        return learnings.first
    }

    private func generateDefaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d"
        return "Reflection on \(formatter.string(from: Date()))"
    }

    // MARK: - Views

    private var emptyState: some View {
        VStack(spacing: Constants.Spacing.lg) {
            EmptyStateView(
                icon: "text.book.closed",
                title: "Start Your Journey",
                subtitle: "Capture your first learning reflection",
                buttonTitle: "Create Reflection",
                buttonAction: {
                    showEditor = true
                }
            )
        }
    }

    private var noResultsState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            subtitle: viewModel?.hasActiveFilters ?? false ? "No reflections match your filters" : "Try different keywords",
            buttonTitle: "Clear Search",
            buttonAction: {
                viewModel?.updateSearchQuery("")
            }
        )
    }

    private var reflectionList: some View {
        List {
            ForEach(viewModel?.sortedDateGroups ?? [], id: \.self) { group in
                if let reflections = viewModel?.groupedReflections[group], !reflections.isEmpty {
                    Section {
                        ForEach(reflections) { reflection in
                            NavigationLink(value: reflection) {
                                ReflectionCard(reflection: reflection)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel?.deleteReflection(reflection)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    reflectionToMove = reflection
                                } label: {
                                    Label("Move", systemImage: "folder")
                                }
                                .tint(.blue)
                            }
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(group.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.leading, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }
        }
    }

    private var sortingMenu: some View {
        Section("Sort By") {
            ForEach(Constants.SortOption.allCases, id: \.self) { option in
                Button {
                    viewModel?.updateSortOption(option)
                } label: {
                    HStack {
                        Text(option.title)
                        if viewModel?.sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ReflectionListView()
        .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
