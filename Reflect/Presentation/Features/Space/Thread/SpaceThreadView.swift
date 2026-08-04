import PhotosUI
import SwiftUI

/// The "respond" page for one reflection. It deliberately shows only the prompt and *your
/// own* responses (with a multiline composer) so you write your answer without anchoring on
/// what others said. A toolbar button opens `SpaceAllResponsesView` to see everyone's.
struct SpaceThreadView: View {
    @State private var viewModel: SpaceThreadViewModel
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var showImageFullscreen = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    init(space: Space, reflection: SpaceReflection) {
        _viewModel = State(initialValue: DIContainer.shared.makeSpaceThreadViewModel(reflection: reflection, space: space))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    header
                    Divider()
                    questionsSection
                }
                .padding(Constants.Spacing.md)
            }
            .refreshable { await viewModel.refresh() }

            composerBar
        }
        .navigationTitle("Your feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SpaceAllResponsesView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        if !viewModel.answers.isEmpty {
                            Text("\(viewModel.answers.count)")
                        }
                    }
                }
                .accessibilityLabel("View all feedback")
            }
        }
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .spaceRemoteChangeReceived)) { _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
        .errorAlert($viewModel.errorMessage)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text(viewModel.reflection.title)
                .font(.title3.weight(.bold))

            if !viewModel.reflection.promptText.isEmpty {
                Text(viewModel.reflection.promptText)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let imageData = viewModel.reflection.imageData,
               let uiImage = UIImage(data: imageData) {
                Button {
                    showImageFullscreen = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(.rect(cornerRadius: Constants.CornerRadius.medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attached photo")
                .fullScreenCover(isPresented: $showImageFullscreen) {
                    ImageFullscreenViewer(
                        images: [FullscreenImage(id: UUID(), image: uiImage)],
                        startingIndex: 0
                    )
                }
            }

            HStack(spacing: 4) {
                Text(SpaceAuthor.label(isMine: viewModel.reflection.isMine, name: viewModel.reflection.authorDisplayName))
                    .fontWeight(.medium)
                if let createdAt = viewModel.reflection.createdAt {
                    Text("·")
                    Text(createdAt, format: .relative(presentation: .named))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Questions

    @ViewBuilder
    private var questionsSection: some View {
        Text("Questions")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        ForEach(Array(viewModel.reflection.questions.enumerated()), id: \.element.id) { index, question in
            let mine = viewModel.myAnswer(for: question.id)
            Button {
                viewModel.select(questionId: question.id)
                composerFocused = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Constants.Spacing.xs) {
                        Text("Q\(index + 1). \(question.text)")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if mine != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.primaryDefault)
                        }
                    }
                    if let mine {
                        Text(mine.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .contextMenu {
                                Button {
                                    viewModel.select(questionId: question.id)
                                    composerFocused = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteOwnAnswer(for: question.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(Constants.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                        .fill(viewModel.activeQuestionId == question.id ? Color.primaryDefault.opacity(0.10) : Color.secondary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Composer

    private var composerBar: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Divider()
            if let activeQuestion = viewModel.activeQuestion {
                replyingToChip(activeQuestion)
            }
            if let draftImage = viewModel.draftImage {
                draftImageThumbnail(draftImage)
            }
            HStack(alignment: .bottom, spacing: Constants.Spacing.sm) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(viewModel.activeQuestionId == nil ? Color.secondary : Color.primaryDefault)
                        .frame(width: 36, height: 36)
                }
                .disabled(viewModel.activeQuestionId == nil)
                .accessibilityLabel("Attach photo")

                TextField("Share your answer…", text: $viewModel.draft, axis: .vertical)
                    .focused($composerFocused)
                    .lineLimit(1...6)
                    .padding(Constants.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                            .fill(Color.secondary.opacity(0.12))
                    )

                if viewModel.isPosting {
                    ProgressView().frame(width: 36, height: 36)
                } else {
                    Button {
                        composerFocused = false
                        Task {
                            await viewModel.submit()
                            selectedPhotoItem = nil
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(viewModel.canPost ? Color.primaryDefault : Color.secondary)
                    }
                    .accessibilityLabel("Send answer")
                    .disabled(!viewModel.canPost)
                }
            }
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.vertical, Constants.Spacing.xs)
        }
        .background(.bar)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.draftImage = image
                }
            }
        }
    }

    private func replyingToChip(_ question: SpaceQuestion) -> some View {
        let index = (viewModel.reflection.questions.firstIndex(where: { $0.id == question.id }) ?? 0) + 1
        return HStack(spacing: Constants.Spacing.xs) {
            Image(systemName: viewModel.isEditingExistingAnswer ? "pencil" : "arrowshape.turn.up.left")
                .font(.caption)
            Text(viewModel.isEditingExistingAnswer ? "Editing Q\(index): \(question.text)" : "Replying to Q\(index): \(question.text)")
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                viewModel.clearDraftPrefill()
                selectedPhotoItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Clear draft")
        }
        .foregroundStyle(Color.primaryDefault)
        .padding(.horizontal, Constants.Spacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primaryDefault.opacity(0.10)))
        .padding(.horizontal, Constants.Spacing.md)
    }

    private func draftImageThumbnail(_ image: UIImage) -> some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: Constants.CornerRadius.small))
            Spacer(minLength: 0)
            Button(role: .destructive) {
                viewModel.draftImage = nil
                selectedPhotoItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Remove photo")
        }
        .padding(.horizontal, Constants.Spacing.md)
    }
}

/// The full answer list for a reflection — everyone's, including yours, across every
/// question. Own answers can be deleted (edit happens back on the respond page, via
/// selecting the question); every answer can be reported.
struct SpaceAllResponsesView: View {
    let viewModel: SpaceThreadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                if viewModel.answers.isEmpty {
                    Text("No feedback yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Constants.Spacing.xl)
                } else {
                    ForEach(viewModel.answers) { answer in
                        // Edit/Delete only render for own answers (guarded by `answer.isMine`
                        // inside `AnswerBubble`), so passing them for every row is safe.
                        AnswerBubble(
                            answer: answer,
                            spaceName: viewModel.space.name,
                            onEdit: {
                                viewModel.select(questionId: answer.questionId)
                                dismiss()
                            },
                            onDelete: { Task { await viewModel.deleteOwnAnswer(for: answer.questionId) } }
                        )
                    }
                }
            }
            .padding(Constants.Spacing.md)
        }
        .navigationTitle("All feedback")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
    }
}

/// A single answer, styled for own vs others'. Context menu offers Edit/Delete (own, with a
/// delete confirmation) and Report (any). Shows a photo thumbnail with a fullscreen viewer
/// when the answer has an attached image.
struct AnswerBubble: View {
    let answer: SpaceAnswer
    let spaceName: String
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showImageFullscreen = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(SpaceAuthor.label(isMine: answer.isMine, name: answer.authorDisplayName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(answer.isMine ? Color.primaryDefault : .secondary)
                if let createdAt = answer.createdAt {
                    Text("·")
                    Text(createdAt, format: .relative(presentation: .named))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(answer.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let imageData = answer.imageData, let uiImage = UIImage(data: imageData) {
                Button {
                    showImageFullscreen = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 88, height: 88)
                        .clipShape(.rect(cornerRadius: Constants.CornerRadius.small))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attached photo")
                .fullScreenCover(isPresented: $showImageFullscreen) {
                    ImageFullscreenViewer(
                        images: [FullscreenImage(id: UUID(), image: uiImage)],
                        startingIndex: 0
                    )
                }
            }
        }
        .padding(Constants.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(answer.isMine ? Color.primaryDefault.opacity(0.10) : Color.secondary.opacity(0.08))
        )
        .contextMenu {
            if answer.isMine {
                if let onEdit {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                }
                if onDelete != nil {
                    Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
                }
            }
            ReportContentButton(contentKind: "feedback", contentID: answer.id, spaceName: spaceName)
        }
        .confirmationDialog(
            "Delete your answer? This can't be undone.",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// A single response, styled for own vs others'. Context menu offers Edit/Delete on your
/// own and Report on any.
struct ResponseBubble: View {
    let response: SpaceResponse
    let spaceName: String
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(SpaceAuthor.label(isMine: response.isMine, name: response.authorDisplayName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(response.isMine ? Color.primaryDefault : .secondary)
                if let createdAt = response.createdAt {
                    Text("·")
                    Text(createdAt, format: .relative(presentation: .named))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(response.body)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Constants.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(response.isMine ? Color.primaryDefault.opacity(0.10) : Color.secondary.opacity(0.08))
        )
        .contextMenu {
            if response.isMine {
                if let onEdit {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                }
                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                }
            }
            ReportContentButton(contentKind: "feedback", contentID: response.id, spaceName: spaceName)
        }
    }
}

/// A small sheet for editing a response body (multiline, counter-validated).
struct SpaceResponseEditSheet: View {
    let limit: Int
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(initialBody: String, limit: Int, onSave: @escaping (String) async -> Bool) {
        self.limit = limit
        self.onSave = onSave
        _text = State(initialValue: initialBody)
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= limit && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feedback", text: $text, axis: .vertical)
                        .lineLimit(3...12)
                } footer: {
                    HStack {
                        Spacer()
                        Text("\(text.count)/\(limit)")
                            .foregroundStyle(text.count > limit ? Color.error : .secondary)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("Edit Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                isSaving = true
                                let saved = await onSave(text)
                                isSaving = false
                                if saved { dismiss() }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
        }
    }
}
