import SwiftUI
import SwiftData
import AVFoundation

struct ReflectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Learning.sortOrder) private var learnings: [Learning]
    @Query(sort: \Reflection.createdAt, order: .reverse) private var reflections: [Reflection]

    @State private var searchText = ""
    @State private var showFilters = false
    @State private var sortOption: Constants.SortOption = .newestFirst

    // Quick action states
    @State private var showActionMenu = false
    @State private var showCameraPicker = false
    @State private var showVoiceRecorder = false
    @State private var showNoLearningAlert = false
    @State private var quickReflectionError: String?
    @State private var showEditor = false

    @Namespace private var menuNamespace

    private var filteredReflections: [Reflection] {
        var result = reflections

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { reflection in
                reflection.title.lowercased().contains(query) ||
                reflection.plainTextContent.lowercased().contains(query)
            }
        }

        // Sort
        switch sortOption {
        case .newestFirst:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            result.sort { $0.createdAt < $1.createdAt }
        case .alphabeticalAZ:
            result.sort { $0.title.lowercased() < $1.title.lowercased() }
        case .alphabeticalZA:
            result.sort { $0.title.lowercased() > $1.title.lowercased() }
        case .recentlyUpdated:
            result.sort { $0.updatedAt > $1.updatedAt }
        }

        return result
    }

    private var groupedReflections: [(String, [Reflection])] {
        let grouped = Dictionary(grouping: filteredReflections) { reflection in
            reflection.createdAt.sectionHeader
        }
        return grouped.sorted { $0.value.first?.createdAt ?? Date() > $1.value.first?.createdAt ?? Date() }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if reflections.isEmpty {
                        emptyState
                    } else if filteredReflections.isEmpty {
                        noResultsState
                    } else {
                        reflectionList
                    }
                }

                // FAB with quick actions
                if !reflections.isEmpty {
                    quickActionMenu
                        .padding(Constants.Spacing.lg)
                }
            }
            .navigationTitle("Reflections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        sortingMenu
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search reflections...")
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            cameraPickerView
        }
        .fullScreenCover(isPresented: $showEditor) {
            ReflectionEditorView(mode: .create)
        }
        .sheet(isPresented: $showVoiceRecorder) {
            voiceRecorderSheet
        }
        .alert("No Learning", isPresented: $showNoLearningAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please create a Learning first before adding reflections")
        }
        .alert("Error", isPresented: .constant(quickReflectionError != nil)) {
            Button("OK", role: .cancel) {
                quickReflectionError = nil
            }
        } message: {
            if let error = quickReflectionError {
                Text(error)
            }
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
                guard let learning = getLearningForQuickReflection() else {
                    showNoLearningAlert = true
                    return
                }
                showCameraPicker = true
            },
            onVoiceTap: {
                // Validate Learning exists before opening voice recorder
                guard let learning = getLearningForQuickReflection() else {
                    showNoLearningAlert = true
                    return
                }
                showVoiceRecorder = true
            }
        )
        .longPressToExpand($showActionMenu) {
            // Long press - expand menu
        }
    }

    // MARK: - Camera Picker

    private var cameraPickerView: some View {
        ImagePickerView(
            sourceType: .camera,
            onPhotoPicked: { image in
                Task {
                    await handlePhotoPicked(image)
                }
                showCameraPicker = false
            },
            onVideoPicked: { url, thumbnail, duration in
                Task {
                    await handleVideoPicked(url: url, thumbnail: thumbnail, duration: duration)
                }
                showCameraPicker = false
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Voice Recorder Sheet

    private var voiceRecorderSheet: some View {
        VoiceRecorderView(isPresented: $showVoiceRecorder) { recording in
            Task {
                await handleVoiceRecording(recording)
            }
        }
    }

    // MARK: - Handlers

    @MainActor
    private func handlePhotoPicked(_ image: UIImage) async {
        guard let learning = getLearningForQuickReflection() else {
            showNoLearningAlert = true
            return
        }

        let modelContext = modelContext
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
            quickReflectionError = "Failed to process image"
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
            quickReflectionError = "Failed to load video"
            return
        }

        // Generate thumbnail as JPEG
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            quickReflectionError = "Failed to process thumbnail"
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
            duration: recording.duration
        )
        voiceRecording.sortOrder = 0
        reflection.voiceRecordings.append(voiceRecording)

        // Save
        modelContext.insert(reflection)
        try? modelContext.save()

        // Track last used learning
        UserDefaults.standard.setLastUsedLearningId(learning.id)

        HapticManager.shared.success()
    }

    // MARK: - Helper Methods

    private func getLearningForQuickReflection() -> Learning? {
        // Try last used first
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
                    // Navigation handled by NavigationLink
                }
            )

            NavigationLink(destination: ReflectionEditorView(mode: .create)) {
                PrimaryButton("Create First Reflection", icon: "plus") {}
            }
            .frame(maxWidth: 250)
        }
    }

    private var noResultsState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            subtitle: "Try different keywords",
            buttonTitle: "Clear Search",
            buttonAction: {
                searchText = ""
            }
        )
    }

    private var reflectionList: some View {
        List {
            ForEach(groupedReflections, id: \.0) { section, sectionReflections in
                Section {
                    ForEach(sectionReflections) { reflection in
                        NavigationLink(destination: ReflectionDetailView(reflection: reflection)) {
                            ReflectionCard(reflection: reflection) {}
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    DateSectionHeader(date: sectionReflections.first?.createdAt ?? Date())
                        .background(Color(.systemBackground).opacity(0.95))
                }
            }

            .padding(.horizontal, Constants.Spacing.md)
            .padding(.bottom, 50) // Space for FAB

        }
    }

    private var sortingMenu: some View {
        Section("Sort By") {
            ForEach(Constants.SortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Text(option.title)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Date Extension for Section Headers

private extension Date {
    var sectionHeader: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else if calendar.isDate(self, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(self, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: self)
        }
    }
}

#Preview {
    ReflectionListView()
        .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
