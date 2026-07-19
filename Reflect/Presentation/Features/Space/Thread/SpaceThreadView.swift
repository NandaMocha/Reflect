import SwiftUI

/// The "respond" page for one reflection. It deliberately shows only the prompt and *your
/// own* responses (with a multiline composer) so you write your answer without anchoring on
/// what others said. A toolbar button opens `SpaceAllResponsesView` to see everyone's.
struct SpaceThreadView: View {
    @State private var viewModel: SpaceThreadViewModel
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var responseToEdit: SpaceResponse?

    init(space: Space, reflection: SpaceReflection) {
        _viewModel = State(initialValue: DIContainer.shared.makeSpaceThreadViewModel(reflection: reflection, space: space))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    header
                    Divider()
                    yourResponses
                }
                .padding(Constants.Spacing.md)
            }
            .refreshable { await viewModel.refresh() }

            composerBar
        }
        .navigationTitle("Your response")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SpaceAllResponsesView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        if !viewModel.responses.isEmpty {
                            Text("\(viewModel.responses.count)")
                        }
                    }
                }
                .accessibilityLabel("View all responses")
            }
        }
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .spaceRemoteChangeReceived)) { _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
        .sheet(item: $responseToEdit) { response in
            SpaceResponseEditSheet(initialBody: response.body, limit: viewModel.responseLimit) { newBody in
                await viewModel.edit(response, body: newBody)
            }
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

    // MARK: - Your responses

    @ViewBuilder
    private var yourResponses: some View {
        if viewModel.myResponses.isEmpty {
            Text("Write your response below. You can see everyone else's from the button above once you're ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Constants.Spacing.lg)
        } else {
            Text("Your responses")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.myResponses) { response in
                ResponseBubble(
                    response: response,
                    spaceName: viewModel.space.name,
                    onEdit: { responseToEdit = response },
                    onDelete: { Task { await viewModel.deleteOwn(response) } }
                )
            }
        }
    }

    // MARK: - Composer

    private var composerBar: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Divider()
            HStack(alignment: .bottom, spacing: Constants.Spacing.sm) {
                TextField("Add your response…", text: $viewModel.draft, axis: .vertical)
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
                        Task { await viewModel.post() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(viewModel.canPost ? Color.accentColor : Color.secondary)
                    }
                    .disabled(!viewModel.canPost)
                }
            }
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.vertical, Constants.Spacing.xs)
        }
        .background(.bar)
    }
}

/// The full response list for a reflection — everyone's, including yours. Own responses can
/// be edited/deleted; every response can be reported. Composing stays on the respond page.
struct SpaceAllResponsesView: View {
    let viewModel: SpaceThreadViewModel
    @State private var responseToEdit: SpaceResponse?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                if viewModel.responses.isEmpty {
                    Text("No responses yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Constants.Spacing.xl)
                } else {
                    ForEach(viewModel.responses) { response in
                        // Edit/Delete only render for own responses (guarded inside the
                        // bubble by `response.isMine`), so passing them for every row is safe.
                        ResponseBubble(
                            response: response,
                            spaceName: viewModel.space.name,
                            onEdit: { responseToEdit = response },
                            onDelete: { Task { await viewModel.deleteOwn(response) } }
                        )
                    }
                }
            }
            .padding(Constants.Spacing.md)
        }
        .navigationTitle("All responses")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        .sheet(item: $responseToEdit) { response in
            SpaceResponseEditSheet(initialBody: response.body, limit: viewModel.responseLimit) { newBody in
                await viewModel.edit(response, body: newBody)
            }
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
                    .foregroundStyle(response.isMine ? Color.accentColor : .secondary)
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
                .fill(response.isMine ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
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
            ReportContentButton(contentKind: "response", contentID: response.id, spaceName: spaceName)
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
                    TextField("Response", text: $text, axis: .vertical)
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
            .navigationTitle("Edit Response")
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
