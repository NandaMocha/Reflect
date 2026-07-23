import SwiftUI
import CloudKit

/// Who's in a space, presented as a sheet from the space's detail screen.
///
/// The owner gets an **Invite People** button that hands off to the system sharing
/// controller (`CloudSharingView`) — the same controller that manages and removes
/// participants, which is the moderation path App Review was told about
/// (docs/features/space-appreview-notes.md). Participants see the roster read-only,
/// because CloudKit only lets the owner change membership.
struct SpaceMembersView: View {
    @State private var viewModel: SpaceMembersViewModel
    @Environment(\.dismiss) private var dismiss

    /// Display-name capture. Opened only when the user taps the "Your name" row — never
    /// presented automatically on open.
    @State private var showNamePrompt = false
    @State private var draftName = ""

    /// Must match the entitlement / `SpaceCloudService`'s container identifier.
    private let spaceContainer = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")

    init(space: Space) {
        _viewModel = State(initialValue: DIContainer.shared.makeSpaceMembersViewModel(space: space))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.showsLoadingState {
                    loadingState
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    memberList
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.load()
            }
            .errorAlert($viewModel.errorMessage)
            .alert("Your name", isPresented: $showNamePrompt) {
                TextField("Display name", text: $draftName)
                Button("Save") {
                    let name = draftName
                    Task { await viewModel.saveDisplayName(name) }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Choose the name other members of this space will see.")
            }
            // Presented once the share has been fetched; clearing it on dismiss also
            // re-reads the roster, so a just-sent invite shows up immediately.
            .sheet(
                isPresented: Binding(
                    get: { viewModel.shareToPresent != nil },
                    set: { if !$0 { Task { await viewModel.inviteSheetDismissed() } } }
                )
            ) {
                if let share = viewModel.shareToPresent {
                    CloudSharingView(
                        share: share,
                        container: spaceContainer,
                        spaceName: viewModel.space.name,
                        onSaved: { Task { await viewModel.inviteSheetDismissed() } },
                        onStopped: { Task { await viewModel.inviteSheetDismissed() } },
                        onError: { _ in Task { await viewModel.inviteSheetDismissed() } }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - List

    private var memberList: some View {
        List {
            Section {
                ForEach(viewModel.members) { member in
                    SpaceMemberRow(member: member)
                }
            } header: {
                Text(rosterSummary)
            } footer: {
                if viewModel.canInvite {
                    Text("Anyone you invite can read and give feedback. Tap Invite People to send an invite or remove someone.")
                } else {
                    Text("Only the space's owner can invite or remove people.")
                }
            }

            if viewModel.canInvite {
                Section {
                    Button {
                        Task { await viewModel.prepareInvite() }
                    } label: {
                        HStack(spacing: Constants.Spacing.sm) {
                            if viewModel.isPreparingInvite {
                                ProgressView()
                            } else {
                                Image(systemName: "person.badge.plus")
                            }
                            Text("Invite People")
                        }
                    }
                    .disabled(viewModel.isPreparingInvite)
                }
            }

            Section {
                Button {
                    draftName = viewModel.myDisplayName
                    showNamePrompt = true
                } label: {
                    HStack {
                        Text("Your name")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(viewModel.myDisplayName.isEmpty ? "Set name" : viewModel.myDisplayName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } footer: {
                Text("This is how you appear to other members of this space.")
            }
        }
        .refreshable { await viewModel.load() }
    }

    /// e.g. "3 members · 1 invited". The invited clause is dropped when there are none.
    private var rosterSummary: String {
        let joined = "\(viewModel.joinedCount) member\(viewModel.joinedCount == 1 ? "" : "s")"
        guard viewModel.invitedCount > 0 else { return joined }
        return "\(joined) · \(viewModel.invitedCount) invited"
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Constants.Spacing.md) {
            NativeLoadingSpinner()
            Text("Loading members…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "person.2",
            title: "No members yet",
            subtitle: viewModel.canInvite
                ? "Invite people you trust to read and give feedback."
                : "This space has no other members yet.",
            buttonTitle: viewModel.canInvite ? "Invite People" : nil,
            buttonAction: viewModel.canInvite ? { Task { await viewModel.prepareInvite() } } : nil
        )
    }
}

// MARK: - Row

/// One member: initials avatar, name (or the handle an invite was sent to), and badges
/// for role, pending status, and read-only permission.
struct SpaceMemberRow: View {
    let member: SpaceMember

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                // Only worth a second line when it isn't already the title.
                if let handle = member.contactHandle, handle != member.displayTitle {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Constants.Spacing.xs) {
                // Once your row shows your chosen name (not "You"), this badge is how you
                // still spot yourself in the roster.
                if member.isMe, let name = member.displayName, !name.isEmpty {
                    badge("You", color: .secondary)
                }
                if member.role == .owner {
                    badge("Owner", color: .primaryDefault)
                }
                if member.status == .invited {
                    badge("Invited", color: .warning)
                } else if !member.canPost {
                    badge("Read only", color: .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.12))
            Text(member.initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 36, height: 36)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

#Preview {
    List {
        SpaceMemberRow(member: SpaceMember(
            id: "1", displayName: "Nanda Mochammad", contactHandle: nil,
            role: .owner, status: .joined, canPost: true, isMe: true
        ))
        SpaceMemberRow(member: SpaceMember(
            id: "2", displayName: "Rani Putri", contactHandle: "rani@example.com",
            role: .member, status: .joined, canPost: true, isMe: false
        ))
        SpaceMemberRow(member: SpaceMember(
            id: "3", displayName: nil, contactHandle: "budi@example.com",
            role: .member, status: .invited, canPost: true, isMe: false
        ))
    }
}
