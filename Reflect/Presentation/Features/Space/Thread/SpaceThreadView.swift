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
    @State private var showEditQuestions = false
    @State private var noteExpanded = false

    init(space: Space, reflection: SpaceReflection) {
        _viewModel = State(initialValue: DIContainer.shared.makeSpaceThreadViewModel(reflection: reflection, space: space))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    header
                    Divider()
                    yourAnswersSection
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
            if viewModel.reflection.isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEditQuestions = true
                        } label: {
                            Label("Edit questions", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Reflection options")
                }
            }
        }
        .sheet(isPresented: $showEditQuestions) {
            SpaceReflectionEditView(
                viewModel: DIContainer.shared.makeSpaceReflectionEditViewModel(reflection: viewModel.reflection, space: viewModel.space),
                onSave: { updated in
                    Task { await viewModel.applyEditedReflection(updated) }
                }
            )
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
            HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(viewModel.reflection.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(3)

                    if let note = viewModel.reflection.note, !note.isEmpty {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(noteExpanded ? nil : 3)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: Constants.Animation.quickDuration)) {
                                    noteExpanded.toggle()
                                }
                            }
                    }
                }

                Spacer(minLength: 0)

                if let imageData = viewModel.reflection.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Button {
                        showImageFullscreen = true
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 88, height: 88)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Your answers

    @ViewBuilder
    private var yourAnswersSection: some View {
        let questions = viewModel.reflection.questions
        if questions.count > 1 {
            Picker("Question", selection: $viewModel.selectedQuestionId) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    questionSegmentLabel(index: index, question: question)
                        .tag(question.id)
                }
            }
            .pickerStyle(.segmented)
        }

        if let selectedQuestion = viewModel.selectedQuestion {
            Text(selectedQuestion.text)
                .font(questions.count > 1 ? .subheadline.weight(.semibold) : .headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        let myAnswers = viewModel.myAnswers(for: viewModel.selectedQuestionId)
        Text("Your answers / \(myAnswers.count)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

        ForEach(myAnswers) { answer in
            AnswerBubble(
                answer: answer,
                spaceName: viewModel.space.name,
                questionNumber: (questions.firstIndex(where: { $0.id == answer.questionId }) ?? 0) + 1,
                onEdit: {
                    viewModel.beginEditing(answer)
                    composerFocused = true
                },
                onDelete: { Task { await viewModel.deleteOwnAnswer(answer) } }
            )
        }
    }

    @ViewBuilder
    private func questionSegmentLabel(index: Int, question: SpaceQuestion) -> some View {
        if viewModel.myAnswerCount(for: question.id) > 0 {
            Label {
                Text("Q\(index + 1)")
            } icon: {
                Circle()
                    .fill(Color.primaryDefault)
                    .frame(width: 6, height: 6)
            }
        } else {
            Text("Q\(index + 1)")
        }
    }

    // MARK: - Composer

    private var composerBar: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Divider()
            composerCaption
            if let draftImage = viewModel.draftImage {
                draftImageThumbnail(draftImage)
            }
            HStack(alignment: .bottom, spacing: Constants.Spacing.sm) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(Color.primaryDefault)
                        .frame(width: 36, height: 36)
                }
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

    private var composerCaption: some View {
        let isEditing = viewModel.editingAnswerID != nil
        let index = (viewModel.reflection.questions.firstIndex(where: { $0.id == viewModel.selectedQuestionId }) ?? 0) + 1
        return HStack(spacing: Constants.Spacing.xs) {
            Text(isEditing ? "Editing your answer" : "Posting to Q\(index)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isEditing {
                Spacer(minLength: 0)
                Button {
                    viewModel.cancelEditing()
                    selectedPhotoItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Cancel editing")
            }
        }
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
