import SwiftUI
import PhotosUI

/// A space's detail: its reflections, with compose, delete-own, and report. Each row taps
/// through to the response thread (T21). Replaces T14's placeholder navigation destination.
struct SpaceDetailView: View {
    @State private var viewModel: SpaceDetailViewModel
    @State private var showCompose = false
    @State private var showMembers = false
    @State private var reflectionToDelete: SpaceReflection?
    @State private var reflectionToEdit: SpaceReflection?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase

    init(space: Space) {
        _viewModel = State(initialValue: DIContainer.shared.makeSpaceDetailViewModel(space: space))
    }

    var body: some View {
        Group {
            if viewModel.reflections.isEmpty {
                emptyState
            } else {
                reflectionList
            }
        }
        .navigationTitle(viewModel.space.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Ask for Feedback")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMembers = true
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("Members")
            }
        }
        .navigationDestination(for: SpaceReflection.self) { reflection in
            SpaceThreadView(space: viewModel.space, reflection: reflection)
        }
        .sheet(isPresented: $showCompose) {
            composeSheet
        }
        .sheet(isPresented: $showMembers) {
            SpaceMembersView(space: viewModel.space)
        }
        .sheet(item: $reflectionToEdit) { reflection in
            SpaceReflectionEditView(
                viewModel: DIContainer.shared.makeSpaceReflectionEditViewModel(reflection: reflection, space: viewModel.space),
                onSave: { updated in viewModel.updateReflection(updated) }
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
        .firstOpenIntro(.space, flagKey: Constants.UserDefaults.hasSeenSpaceIntro)
        .alert(
            "Delete request?",
            isPresented: Binding(
                get: { reflectionToDelete != nil },
                set: { if !$0 { reflectionToDelete = nil } }
            ),
            presenting: reflectionToDelete
        ) { reflection in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteOwn(reflection) }
                reflectionToDelete = nil
            }
            Button("Cancel", role: .cancel) { reflectionToDelete = nil }
        } message: { _ in
            Text("This deletes your feedback request and all its feedback for everyone.")
        }
    }

    // MARK: - List

    private var reflectionList: some View {
        List {
            ForEach(viewModel.groupedReflections, id: \.group) { entry in
                Section {
                    ForEach(entry.reflections) { reflection in
                        NavigationLink(value: reflection) {
                            SpaceReflectionRow(reflection: reflection)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if reflection.isMine {
                                Button(role: .destructive) {
                                    reflectionToDelete = reflection
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .contextMenu {
                            if reflection.isMine {
                                Button {
                                    reflectionToEdit = reflection
                                } label: {
                                    Label("Edit questions", systemImage: "pencil")
                                }
                            }
                            ReportContentButton(
                                contentKind: "request",
                                contentID: reflection.id,
                                spaceName: viewModel.space.name
                            )
                        }
                    }
                } header: {
                    Text(entry.group.title)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "text.bubble",
            title: "No feedback requests yet",
            subtitle: "Ask your space for feedback on what you're learning.",
            buttonTitle: "Ask for Feedback",
            buttonAction: { showCompose = true }
        )
    }

    // MARK: - Compose

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want feedback on?", text: $viewModel.newTitle)
                } footer: {
                    HStack {
                        Spacer()
                        Text("\(viewModel.titleCount)/\(viewModel.titleLimit)")
                            .foregroundStyle(viewModel.titleCount > viewModel.titleLimit ? Color.error : .secondary)
                            .monospacedDigit()
                    }
                }

                Section {
                    TextField("Add context (optional)…", text: $viewModel.newNote, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Note")
                } footer: {
                    HStack {
                        Spacer()
                        Text("\(viewModel.newNote.count)/\(viewModel.noteLimit)")
                            .foregroundStyle(viewModel.newNote.count > viewModel.noteLimit ? Color.error : .secondary)
                            .monospacedDigit()
                    }
                }

                SpaceQuestionListEditor(questions: $viewModel.newQuestions)

                Section {
                    if let image = viewModel.newImage {
                        HStack(spacing: Constants.Spacing.md) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(.rect(cornerRadius: Constants.CornerRadius.small))

                            Spacer()

                            Button(role: .destructive) {
                                viewModel.newImage = nil
                                selectedPhotoItem = nil
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    } else {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Add Photo", systemImage: "photo")
                        }
                    }
                } footer: {
                    Text("The photo is compressed before sharing to keep the space light.")
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.newImage = image
                    }
                }
            }
            .navigationTitle("Ask for Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCompose = false }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Ask") {
                            Task {
                                if await viewModel.save() {
                                    selectedPhotoItem = nil
                                    showCompose = false
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.canSave)
                    }
                }
            }
        }
    }
}

/// One reflection row: title, author + relative date, and a response-count affordance.
struct SpaceReflectionRow: View {
    let reflection: SpaceReflection

    var body: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reflection.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                if let firstQuestion = reflection.questions.first {
                    HStack(alignment: .top, spacing: 8) {
                        Text(firstQuestion.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if reflection.questions.count > 1 {
                            Text("\(reflection.questions.count) questions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text(SpaceAuthor.label(isMine: reflection.isMine, name: reflection.authorDisplayName))
                        .fontWeight(.medium)
                    if let createdAt = reflection.createdAt {
                        Text("·")
                        Text(createdAt, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let imageData = reflection.imageData, let thumbnail = UIImage(data: imageData) {
                Spacer(minLength: 0)
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: Constants.CornerRadius.small))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shared helper for rendering a content author: "You" for the current user, the resolved
/// display name otherwise, falling back to "A member".
enum SpaceAuthor {
    static func label(isMine: Bool, name: String?) -> String {
        if isMine { return "You" }
        return name ?? "A member"
    }
}

#Preview {
    NavigationStack {
        SpaceDetailView(space: Space(
            id: "1", name: "Study Group", detail: nil, iconName: "book.fill", colorHex: "3AAFA9", isOwner: true,
            zoneID: SpaceZoneRef(zoneName: "z", ownerName: "o", lane: .privateDB),
            createdAt: Date(), participantCount: 2
        ))
    }
}
