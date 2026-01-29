import SwiftUI
import SwiftData
import PhotosUI

struct ReflectionEditorView: View {
    enum Mode: Equatable {
        case create
        case edit(Reflection)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create): return true
            case let (.edit(r1), .edit(r2)): return r1.id == r2.id
            default: return false
            }
        }
    }

    let mode: Mode
    var preselectedLearning: Learning?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Learning.sortOrder) private var learnings: [Learning]

    // Form State
    @State private var title = ""
    @State private var content = ""
    @State private var selectedLearning: Learning?
    @State private var images: [ImageInput] = []
    @State private var existingImageIds: Set<UUID> = []
    @State private var voiceRecordings: [VoiceRecordingInput] = []
    @State private var selectedDate = Date()

    // UI State
    @State private var showDiscardAlert = false
    @State private var showImagePicker = false
    @State private var showVoiceRecorder = false
    @State private var showLearningPicker = false
    @State private var showDatePicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var hasChanges = false
    @State private var isSaving = false

    @FocusState private var focusedField: Field?

    enum Field {
        case title
        case content
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navigationTitle: String {
        isEditing ? "Edit Reflection" : "New Reflection"
    }

    private var defaultTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d"
        return "Reflection on \(formatter.string(from: selectedDate))"
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedLearning != nil
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                    discardAlertButtons
                } message: {
                    discardAlertMessage
                }
                .sheet(isPresented: $showLearningPicker) { learningPickerSheet }
                .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotoItems, maxSelectionCount: Constants.Limits.maxImagesPerReflection - images.count)
                .sheet(isPresented: $showDatePicker) { datePickerSheet }
                .sheet(isPresented: $showVoiceRecorder) { voiceRecorderSheet }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task { await loadImages(from: newItems) }
                }
                .onAppear { loadExistingData() }
        }
    }

    // MARK: - View Components

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView

                titleField
                    .padding(.bottom, Constants.Spacing.md)

                // Content Section
                contentEditorSection
                    .padding(.bottom, Constants.Spacing.md)

                // Voice Notes Section
                if !voiceRecordings.isEmpty {
                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, Constants.Spacing.md)

                    voiceRecordingsSection
                        .padding(.bottom, Constants.Spacing.md)
                }

                // Images Section
                if !images.isEmpty {
                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, Constants.Spacing.md)

                    imageAttachmentsGallery
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
    }

    private var headerView: some View {
        ReflectionEditorHeaderView(
            selectedLearning: selectedLearning,
            selectedDate: selectedDate,
            onSelectLearning: {
                if !learnings.isEmpty {
                    showLearningPicker = true
                }
            },
            onSelectDate: { showDatePicker = true }
        )
    }

    private var titleField: some View {
        VStack(spacing: Constants.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                if title.isEmpty {
                    Text(defaultTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }

                TextField("", text: $title)
                    .font(.title2.weight(.semibold))
                    .focused($focusedField, equals: .title)
                    .onChange(of: title) { _, _ in hasChanges = true }
            }

            Divider()
                .opacity(0.3)
        }
    }

    private var voiceRecordingsSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            ForEach(Array(voiceRecordings.enumerated()), id: \.offset) { index, recording in
                VoiceRecordingItemView(
                    recording: recording,
                    onPlay: { /* Play recording */ },
                    onRemove: {
                        voiceRecordings.remove(at: index)
                        hasChanges = true
                    }
                )
            }
        }
    }

    private var contentEditorSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("Write your reflection here...")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $content)
                    .font(.body)
                    .focused($focusedField, equals: .content)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .onChange(of: content) { _, _ in hasChanges = true }
            }
            .padding(.horizontal, -4)

            Divider()
                .opacity(0.3)
        }
    }

    private var imageAttachmentsGallery: some View {
        GeometryReader { geometry in
            let columns = 2
            let spacing = Constants.Spacing.xs
            let totalSpacing = CGFloat(columns - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let imageSize = availableWidth / CGFloat(columns)

            LazyVGrid(
                columns: [
                    GridItem(.fixed(imageSize), spacing: spacing),
                    GridItem(.fixed(imageSize), spacing: spacing)
                ],
                spacing: spacing
            ) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, imageInput in
                    ImageAttachmentItemView(
                        image: imageInput.image,
                        onRemove: {
                            images.remove(at: index)
                            hasChanges = true
                        }
                    )
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            cancelButton
        }

        ToolbarItem(placement: .confirmationAction) {
            saveButton
        }

        ToolbarItem(placement: .bottomBar) {
            bottomToolbar
        }
    }

    private var cancelButton: some View {
        Button("Cancel") {
            if hasChanges {
                showDiscardAlert = true
            } else {
                dismiss()
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.primaryDefault)
                .clipShape(Circle())
        }
        .opacity(isValid && !isSaving ? 1.0 : 0.5)
    }

    private var bottomToolbar: some View {
        HStack(spacing: Constants.Spacing.lg) {
            Button { showImagePicker = true } label: {
                Image(systemName: "photo").font(.callout)
            }

            Button { /* Camera */ } label: {
                Image(systemName: "camera").font(.callout)
            }

            Button { showVoiceRecorder = true } label: {
                Image(systemName: "waveform").font(.callout)
            }
        }
        .padding(Constants.Spacing.xxs)
    }

    // MARK: - Sheets & Alerts

    private var discardAlertButtons: some View {
        Group {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        }
    }

    private var discardAlertMessage: some View {
        Text("You have unsaved changes. Are you sure you want to discard them?")
    }

    private var learningPickerSheet: some View {
        LearningPickerSheet(
            selectedLearning: $selectedLearning,
            learnings: learnings,
            onDismiss: {
                hasChanges = true
                showLearningPicker = false
            }
        )
    }

    private var datePickerSheet: some View {
        DatePickerSheet(
            selectedDate: $selectedDate,
            onDismiss: {
                hasChanges = true
                showDatePicker = false
            }
        )
    }

    private var voiceRecorderSheet: some View {
        VoiceRecorderView(isPresented: $showVoiceRecorder) { recording in
            voiceRecordings.append(recording)
            hasChanges = true
        }
    }

    // MARK: - Data Loading

    private func loadExistingData() {
        switch mode {
        case .create:
            // Use preselected learning if provided
            if let learning = preselectedLearning {
                selectedLearning = learning
            }
        case .edit(let reflection):
            title = reflection.title
            content = reflection.plainTextContent
            selectedLearning = reflection.learning
            selectedDate = reflection.createdAt

            // Load Images
            images = reflection.images
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .compactMap { imageAttachment in
                    guard let imageData = imageAttachment.imageData,
                          let image = UIImage(data: imageData) else { return nil }
                    existingImageIds.insert(imageAttachment.id)
                    return ImageInput(
                        id: imageAttachment.id,
                        image: image,
                        caption: imageAttachment.caption
                    )
                }

            // Load Voice Recordings
            voiceRecordings = reflection.voiceRecordings
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .compactMap {
                    guard let data = $0.audioData else { return nil }
                    return VoiceRecordingInput(
                        id: UUID(), // temporary ID for View identity
                        existingId: $0.id,
                        audioData: data,
                        transcription: $0.transcription,
                        language: $0.language,
                        duration: $0.duration
                    )
                }

            hasChanges = false
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let input = ImageInput(image: image)
                await MainActor.run {
                    images.append(input)
                    hasChanges = true
                }
            }
        }
        await MainActor.run {
            selectedPhotoItems = []
        }
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        guard isValid else { return }
        isSaving = true

        do {
            switch mode {
            case .create:
                try await createReflection()
            case .edit(let reflection):
                try await updateReflection(reflection)
            }

            HapticManager.shared.success()
            dismiss()
        } catch {
            HapticManager.shared.error()
        }

        isSaving = false
    }

    private func createReflection() async throws {
        let reflection = Reflection(
            title: title.trimmingCharacters(in: .whitespaces),
            plainTextContent: content.trimmingCharacters(in: .whitespaces)
        )
        reflection.learning = selectedLearning
        reflection.createdAt = selectedDate

        // Add images
        let imageService = ImageProcessingService.shared
        for (index, imageInput) in images.enumerated() {
            if let imageData = imageService.compressImage(imageInput.image, quality: CompressionQuality.high),
               let thumbnailData = imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200)) {
                let attachment = ImageAttachment(
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    caption: imageInput.caption
                )
                attachment.sortOrder = index
                reflection.images.append(attachment)
            }
        }

        // Add voice recordings
        for (index, voiceInput) in voiceRecordings.enumerated() {
            let recording = VoiceRecording(
                audioData: voiceInput.audioData,
                transcription: voiceInput.transcription,
                language: voiceInput.language,
                duration: voiceInput.duration
            )
            recording.sortOrder = index
            reflection.voiceRecordings.append(recording)
        }

        modelContext.insert(reflection)
        try modelContext.save()
    }

    private func updateReflection(_ reflection: Reflection) async throws {
        reflection.title = title.trimmingCharacters(in: .whitespaces)
        reflection.plainTextContent = content.trimmingCharacters(in: .whitespaces)
        reflection.learning = selectedLearning
        reflection.createdAt = selectedDate
        reflection.updatedAt = Date()

        // Sync Images
        let imageService = ImageProcessingService.shared

        // 1. Identify existing image IDs to keep
        let currentImageIds = Set(images.map { $0.id })

        // 2. Remove deleted images from DB
        let imagesToRemove = reflection.images.filter { !currentImageIds.contains($0.id) }
        for image in imagesToRemove {
            modelContext.delete(image)
            if let index = reflection.images.firstIndex(where: { $0.id == image.id }) {
                reflection.images.remove(at: index)
            }
        }

        // 3. Add new images and update existing ones, maintain sort order
        for (index, imageInput) in images.enumerated() {
            if existingImageIds.contains(imageInput.id),
               let existingImage = reflection.images.first(where: { $0.id == imageInput.id }) {
                // Update sort order for existing
                existingImage.sortOrder = index
                existingImage.caption = imageInput.caption
            } else {
                // Create new image
                if let imageData = imageService.compressImage(imageInput.image, quality: .high),
                   let thumbnailData = imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200)) {
                    let newImage = ImageAttachment(
                        imageData: imageData,
                        thumbnailData: thumbnailData,
                        caption: imageInput.caption
                    )
                    newImage.sortOrder = index
                    reflection.images.append(newImage)
                }
            }
        }

        // Sync Voice Recordings

        // 1. Identify existing IDs to keep
        let existingIdsToKeep = Set(voiceRecordings.compactMap { $0.existingId })

        // 2. Remove deleted recordings from DB
        let recordingsToRemove = reflection.voiceRecordings.filter { !existingIdsToKeep.contains($0.id) }
        for recording in recordingsToRemove {
            modelContext.delete(recording) // Remove from context and relationship
            if let index = reflection.voiceRecordings.firstIndex(where: { $0.id == recording.id }) {
                reflection.voiceRecordings.remove(at: index)
            }
        }

        // 3. Add new recordings and update sort order
        for (index, input) in voiceRecordings.enumerated() {
            if let existingId = input.existingId,
               let existingRecording = reflection.voiceRecordings.first(where: { $0.id == existingId }) {
                // Update sort order for existing
                existingRecording.sortOrder = index
            } else {
                // Create new
                let newRecording = VoiceRecording(
                    audioData: input.audioData,
                    transcription: input.transcription,
                    language: input.language,
                    duration: input.duration
                )
                newRecording.sortOrder = index
                reflection.voiceRecordings.append(newRecording)
            }
        }

        try modelContext.save()
    }
}

#Preview {
    ReflectionEditorView(mode: .create)
        .modelContainer(for: [Learning.self, Reflection.self, ImageAttachment.self, VoiceRecording.self], inMemory: true)
}
