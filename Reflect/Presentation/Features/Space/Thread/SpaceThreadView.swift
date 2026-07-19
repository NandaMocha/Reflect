import SwiftUI

/// Comment-style thread for one reflection: a header with the prompt, chronological
/// responses, and an always-visible composer. Delete-own via context menu; report on every
/// response.
struct SpaceThreadView: View {
    @State private var viewModel: SpaceThreadViewModel
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(space: Space, reflection: SpaceReflection) {
        _viewModel = State(initialValue: DIContainer.shared.makeSpaceThreadViewModel(reflection: reflection, space: space))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    header

                    Divider()

                    if viewModel.responses.isEmpty {
                        Text("No responses yet. Be the first to reply.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Constants.Spacing.lg)
                    } else {
                        ForEach(viewModel.responses) { response in
                            ResponseBubble(response: response, spaceName: viewModel.space.name) {
                                Task { await viewModel.deleteOwn(response) }
                            }
                        }
                    }
                }
                .padding(Constants.Spacing.md)
            }
            .refreshable { await viewModel.refresh() }

            composerBar
        }
        .navigationTitle("Responses")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .spaceRemoteChangeReceived)) { _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
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

    // MARK: - Composer

    private var composerBar: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Divider()
            HStack(alignment: .bottom, spacing: Constants.Spacing.sm) {
                TextField("Add a response…", text: $viewModel.draft, axis: .vertical)
                    .focused($composerFocused)
                    .lineLimit(1...5)
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

/// A single response, aligned/tinted differently for the current user's own responses.
struct ResponseBubble: View {
    let response: SpaceResponse
    let spaceName: String
    let onDelete: () -> Void

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
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            ReportContentButton(contentKind: "response", contentID: response.id, spaceName: spaceName)
        }
    }
}
