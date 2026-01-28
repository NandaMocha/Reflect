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
    @State private var voiceRecordings: [VoiceRecordingInput] = []
    @State private var hashtags: [String] = []

    // UI State
    @State private var showDiscardAlert = false
    @State private var showImagePicker = false
    @State private var showVoiceRecorder = false
    @State private var showHashtagEditor = false
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

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedLearning != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Constants.Spacing.lg) {
                    learningPicker
                    titleField
                    formattingToolbar
                    contentEditor
                    attachmentsSection
                    hashtagsSection
                }
                .padding(Constants.Spacing.md)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(!isValid || isSaving)
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .keyboard) {
                    keyboardToolbar
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .photosPicker(isPresented: $showImagePicker, selection: $selectedPhotoItems, maxSelectionCount: Constants.Limits.maxImagesPerReflection - images.count)
            .sheet(isPresented: $showVoiceRecorder) {
                VoiceRecorderView(isPresented: $showVoiceRecorder) { recording in
                    voiceRecordings.append(recording)
                    hasChanges = true
                }
            }
            .sheet(isPresented: $showHashtagEditor) {
                HashtagEditorSheet(selectedHashtags: $hashtags) {
                    hasChanges = true
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await loadImages(from: newItems)
                }
            }
            .onAppear {
                loadExistingData()
            }
        }
    }

    // MARK: - Form Sections

    private var learningPicker: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text("Learning")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            if learnings.isEmpty {
                Text("No learnings yet. Create a learning first.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(Constants.Spacing.md)
                    .frame(maxWidth: .infinity)
                    .glassCard()
            } else {
                Menu {
                    ForEach(learnings) { learning in
                        Button {
                            selectedLearning = learning
                            hasChanges = true
                        } label: {
                            Label(learning.title, systemImage: learning.iconName)
                        }
                    }
                } label: {
                    HStack {
                        if let learning = selectedLearning {
                            Image(systemName: learning.iconName)
                                .foregroundColor(Color(hex: learning.colorHex))
                            Text(learning.title)
                                .foregroundColor(.primary)
                        } else {
                            Text("Select a learning...")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding(Constants.Spacing.md)
                    .glassCard()
                }
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text("Title")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            TextField("Enter reflection title...", text: $title)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .title)
                .padding(Constants.Spacing.md)
                .glassCard()
                .onChange(of: title) { _, _ in hasChanges = true }
        }
    }

    private var formattingToolbar: some View {
        FormattingToolbar(text: $content, onInsertDivider: {
            content += "\n---\n"
            hasChanges = true
        })
    }

    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text("Content")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            RichTextEditor(text: $content, minHeight: 200)
                .focused($focusedField, equals: .content)
                .onChange(of: content) { _, _ in hasChanges = true }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text("Attachments")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            AttachmentGrid(
                images: images,
                voiceRecordings: voiceRecordings,
                onRemoveImage: { index in
                    images.remove(at: index)
                    hasChanges = true
                },
                onRemoveVoice: { index in
                    voiceRecordings.remove(at: index)
                    hasChanges = true
                }
            )

            HStack(spacing: Constants.Spacing.sm) {
                Button {
                    showImagePicker = true
                } label: {
                    Label("Photo", systemImage: "photo")
                        .font(.subheadline)
                }
                .disabled(images.count >= Constants.Limits.maxImagesPerReflection)

                Button {
                    showVoiceRecorder = true
                } label: {
                    Label("Voice", systemImage: "mic")
                        .font(.subheadline)
                }
                .disabled(voiceRecordings.count >= Constants.Limits.maxVoiceNotesPerReflection)
            }
            .buttonStyle(.bordered)
        }
    }

    private var hashtagsSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text("Hashtags")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            FlowLayout(spacing: Constants.Spacing.xs) {
                ForEach(hashtags, id: \.self) { tag in
                    HashtagChip(
                        text: tag,
                        isSelected: true,
                        showRemove: true,
                        onRemove: {
                            hashtags.removeAll { $0 == tag }
                            hasChanges = true
                        }
                    )
                }

                Button {
                    showHashtagEditor = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundColor(.primaryDefault)
                        .padding(.horizontal, Constants.Spacing.sm)
                        .padding(.vertical, Constants.Spacing.xs)
                }
            }
        }
    }

    private var keyboardToolbar: some View {
        HStack {
            Button {
                showImagePicker = true
            } label: {
                Image(systemName: "photo")
            }

            Button {
                showVoiceRecorder = true
            } label: {
                Image(systemName: "mic")
            }

            Button {
                showHashtagEditor = true
            } label: {
                Image(systemName: "number")
            }

            Spacer()

            Button {
                focusedField = nil
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
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
            hashtags = reflection.hashtags.map { $0.name }
            // Note: Images and voice recordings would need special handling
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

        // Add hashtags
        for tagName in hashtags {
            let hashtag = Hashtag(name: tagName)
            reflection.hashtags.append(hashtag)
        }

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
        reflection.updatedAt = Date()

        // Update hashtags
        reflection.hashtags.removeAll()
        for tagName in hashtags {
            let hashtag = Hashtag(name: tagName)
            reflection.hashtags.append(hashtag)
        }

        try modelContext.save()
    }
}

// MARK: - Hashtag Editor Sheet

struct HashtagEditorSheet: View {
    @Binding var selectedHashtags: [String]
    let onUpdate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Hashtag.name) private var existingHashtags: [Hashtag]

    @State private var newHashtag = ""

    private var filteredSuggestions: [Hashtag] {
        if newHashtag.isEmpty {
            return existingHashtags.filter { !selectedHashtags.contains($0.name) }
        }
        return existingHashtags.filter {
            $0.name.lowercased().contains(newHashtag.lowercased()) &&
            !selectedHashtags.contains($0.name)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Input
                HStack {
                    Text("#")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    TextField("Add hashtag", text: $newHashtag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            addHashtag()
                        }

                    if !newHashtag.isEmpty {
                        Button("Add") {
                            addHashtag()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()

                Divider()

                // Selected hashtags
                if !selectedHashtags.isEmpty {
                    VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                        Text("Selected")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        FlowLayout(spacing: Constants.Spacing.xs) {
                            ForEach(selectedHashtags, id: \.self) { tag in
                                HashtagChip(
                                    text: tag,
                                    isSelected: true,
                                    showRemove: true,
                                    onRemove: {
                                        selectedHashtags.removeAll { $0 == tag }
                                        onUpdate()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)

                    Divider()
                }

                // Suggestions
                if !filteredSuggestions.isEmpty {
                    List {
                        Section("Suggestions") {
                            ForEach(filteredSuggestions) { hashtag in
                                Button {
                                    selectedHashtags.append(hashtag.name)
                                    newHashtag = ""
                                    onUpdate()
                                } label: {
                                    HStack {
                                        Text(hashtag.displayName)
                                        Spacer()
                                        Text("\(hashtag.usageCount)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                Spacer()
            }
            .navigationTitle("Hashtags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addHashtag() {
        let tag = newHashtag.lowercased().trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !selectedHashtags.contains(tag) else { return }

        selectedHashtags.append(tag)
        newHashtag = ""
        onUpdate()
        HapticManager.shared.lightImpact()
    }
}

#Preview {
    ReflectionEditorView(mode: .create)
        .modelContainer(for: [Learning.self, Reflection.self, Hashtag.self], inMemory: true)
}
