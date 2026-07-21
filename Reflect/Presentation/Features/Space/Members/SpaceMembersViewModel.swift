import CloudKit
import Foundation
import Observation

/// Backs the members sheet: who's in a space, plus the owner's invite entry point.
///
/// There's no cache-first paint here (unlike the reflections screens) because membership
/// isn't a record — it only exists on the `CKShare`, so the first read is always a fetch.
@Observable
@MainActor
final class SpaceMembersViewModel {

    // MARK: - State

    let space: Space
    var members: [SpaceMember] = []
    var isLoading: Bool = false
    var errorMessage: String?

    /// Set once the share has been fetched, which is what drives the sharing controller.
    /// Nil until then — the invite button loads it on demand rather than up front.
    var shareToPresent: CKShare?
    var isPreparingInvite: Bool = false

    // MARK: - Dependencies

    private let fetchUseCase: FetchSpaceMembersUseCaseProtocol
    private let repository: SpaceRepositoryProtocol

    // MARK: - Initialization

    init(
        space: Space,
        fetchUseCase: FetchSpaceMembersUseCaseProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.space = space
        self.fetchUseCase = fetchUseCase
        self.repository = repository
    }

    // MARK: - Computed

    /// Only the owner can invite or remove people — CloudKit enforces this server-side, so
    /// showing the control to a participant would just produce a failure.
    var canInvite: Bool { space.isOwner }

    var joinedCount: Int { members.filter { $0.status == .joined }.count }
    var invitedCount: Int { members.filter { $0.status == .invited }.count }

    var isEmpty: Bool { members.isEmpty && !isLoading }

    // MARK: - Actions

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await fetchUseCase.execute(for: space)
            errorMessage = nil
        } catch is CancellationError {
            // Cancelled pull-to-refresh — not a real error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the share and hands it to the view, which presents `CloudSharingView`.
    func prepareInvite() async {
        guard canInvite, !isPreparingInvite else { return }
        isPreparingInvite = true
        defer { isPreparingInvite = false }
        do {
            shareToPresent = try await repository.shareForSpace(space)
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    /// Called when the sharing controller closes. The participant list may have changed
    /// (invites sent, members removed), so re-read it.
    func inviteSheetDismissed() async {
        shareToPresent = nil
        await load()
    }
}
