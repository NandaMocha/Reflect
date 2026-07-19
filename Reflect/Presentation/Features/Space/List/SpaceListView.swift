import SwiftUI

/// The Spaces list: owned + joined spaces with cache-first paint, pull-to-refresh, and
/// the create-space entry point. Owner rows offer Delete (destroys for everyone), joined
/// rows offer Leave (drops only your access) — the copy distinction is a requirement
/// (plan §11.3), not polish.
struct SpaceListView: View {
    @State private var viewModel = DIContainer.shared.makeSpaceListViewModel()
    @State private var showCreateSheet = false
    @State private var spaceToDelete: Space?
    @State private var spaceToLeave: Space?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.showsUnavailableState {
                    unavailableState
                } else if viewModel.spaces.isEmpty {
                    emptyState
                } else {
                    spaceList
                }
            }
            .navigationTitle("Spaces")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.showsUnavailableState)
                }
            }
            .navigationDestination(for: Space.self) { space in
                // Placeholder until T20 swaps in SpaceDetailView.
                Text(space.name)
                    .navigationTitle(space.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .sheet(isPresented: $showCreateSheet, onDismiss: {
                Task { await viewModel.refresh(force: true) }
            }) {
                SpaceFormView()
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
                "Delete Space?",
                isPresented: dialogBinding($spaceToDelete),
                presenting: spaceToDelete
            ) { space in
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(space) }
                    spaceToDelete = nil
                }
                Button("Cancel", role: .cancel) { spaceToDelete = nil }
            } message: { _ in
                Text("Deletes this space and all its content for every member. This cannot be undone.")
            }
            .confirmationDialog(
                "Leave Space?",
                isPresented: dialogBinding($spaceToLeave),
                presenting: spaceToLeave
            ) { space in
                Button("Leave", role: .destructive) {
                    Task { await viewModel.leave(space) }
                    spaceToLeave = nil
                }
                Button("Cancel", role: .cancel) { spaceToLeave = nil }
            } message: { _ in
                Text("You'll lose access. The space and its content remain for other members.")
            }
        }
    }

    // MARK: - List

    private var spaceList: some View {
        List {
            ForEach(viewModel.spaces) { space in
                NavigationLink(value: space) {
                    SpaceRowView(space: space)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if space.isOwner {
                        Button(role: .destructive) {
                            spaceToDelete = space
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } else {
                        Button {
                            spaceToLeave = space
                        } label: {
                            Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh(force: true) }
    }

    // MARK: - States

    private var emptyState: some View {
        EmptyStateView(
            icon: "person.3",
            title: "No shared spaces yet",
            subtitle: "Create a space to reflect together. You'll invite people right after.",
            buttonTitle: "New Space",
            buttonAction: { showCreateSheet = true }
        )
    }

    private var unavailableState: some View {
        EmptyStateView(
            icon: "icloud.slash",
            title: "iCloud Required",
            subtitle: "Sign in to iCloud in Settings to create and join shared spaces."
        )
    }

    // MARK: - Helpers

    /// A presentation binding for a confirmation dialog driven by an optional item:
    /// true while the item is set, and clearing the item when dismissed.
    private func dialogBinding(_ item: Binding<Space?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
    }
}

#Preview {
    SpaceListView()
}
