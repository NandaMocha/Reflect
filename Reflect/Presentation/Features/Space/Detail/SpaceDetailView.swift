import SwiftUI

/// A space's detail: its reflections, with compose, delete-own, and report. Each row taps
/// through to the response thread (T21). Replaces T14's placeholder navigation destination.
struct SpaceDetailView: View {
    @State private var viewModel: SpaceDetailViewModel
    @State private var showCompose = false
    @State private var reflectionToDelete: SpaceReflection?

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
            }
        }
        .navigationDestination(for: SpaceReflection.self) { reflection in
            SpaceThreadView(space: viewModel.space, reflection: reflection)
        }
        .sheet(isPresented: $showCompose) {
            composeSheet
        }
        .task { await viewModel.load() }
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(
            "Delete Reflection?",
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
            Text("This deletes your reflection and all its responses for everyone.")
        }
    }

    // MARK: - List

    private var reflectionList: some View {
        List {
            ForEach(viewModel.reflections) { reflection in
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
                    ReportContentButton(
                        contentKind: "reflection",
                        contentID: reflection.id,
                        spaceName: viewModel.space.name
                    )
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "text.bubble",
            title: "No reflections yet",
            subtitle: "Start the conversation — add a reflection for everyone in this space.",
            buttonTitle: "New Reflection",
            buttonAction: { showCompose = true }
        )
    }

    // MARK: - Compose

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.newTitle)
                } footer: {
                    HStack {
                        Spacer()
                        Text("\(viewModel.titleCount)/\(viewModel.titleLimit)")
                            .foregroundStyle(viewModel.titleCount > viewModel.titleLimit ? Color.error : .secondary)
                            .monospacedDigit()
                    }
                }

                Section("Prompt") {
                    TextField("What should people reflect on?", text: $viewModel.newPrompt, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("New Reflection")
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
                        Button("Add") {
                            Task {
                                if await viewModel.save() { showCompose = false }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(reflection.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)

            if !reflection.promptText.isEmpty {
                Text(reflection.promptText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
            id: "1", name: "Study Group", detail: nil, emoji: "📚", isOwner: true,
            zoneID: SpaceZoneRef(zoneName: "z", ownerName: "o", lane: .privateDB),
            createdAt: Date(), participantCount: 2
        ))
    }
}
