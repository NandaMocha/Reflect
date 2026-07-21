import SwiftUI

/// A space's detail: its reflections, with compose, delete-own, and report. Each row taps
/// through to the response thread (T21). Replaces T14's placeholder navigation destination.
struct SpaceDetailView: View {
    @State private var viewModel: SpaceDetailViewModel
    @State private var showCompose = false
    @State private var showMembers = false
    @State private var reflectionToDelete: SpaceReflection?
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
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .spaceRemoteChangeReceived)) { _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
        .errorAlert($viewModel.errorMessage)
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

                Section("Details") {
                    TextField("Add context or specific questions…", text: $viewModel.newPrompt, axis: .vertical)
                        .lineLimit(3...8)
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
