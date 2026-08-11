import CloudKit
import Foundation
import Observation
import UIKit

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
    /// Flips true once the first roster fetch resolves (success or failure). Gates the empty
    /// state so it can't flash before the initial load — until then the view shows the
    /// loading indicator, keeping it fixed in place instead of appearing after an empty flash.
    var hasLoaded: Bool = false
    var errorMessage: String?

    /// The name the current user appears as to other members. Persisted in UserDefaults and
    /// mirrored into the space's zone so participants can see who's who.
    var myDisplayName: String = UserDefaults.standard.spaceDisplayName() ?? ""

    /// Set once the share has been fetched, which is what drives the sharing controller.
    /// Nil until then — the invite button loads it on demand rather than up front.
    var shareToPresent: CKShare?
    var isPreparingInvite: Bool = false

    /// Drives the invite-link button's spinner while the share is fetched (and, the first
    /// time, made public).
    var isPreparingLink: Bool = false
    /// Flips true once the link is on the pasteboard, so the button can confirm the copy.
    /// Cleared automatically a couple of seconds later by `scheduleCopiedReset()`.
    private(set) var didCopyLink: Bool = false

    // MARK: - Dependencies

    private let fetchUseCase: FetchSpaceMembersUseCaseProtocol
    private let shareLinkUseCase: ShareSpaceInviteLinkUseCaseProtocol
    private let repository: SpaceRepositoryProtocol

    /// Held so a repeat copy can restart the "Link Copied" timer rather than race it.
    private var copiedResetTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        space: Space,
        fetchUseCase: FetchSpaceMembersUseCaseProtocol,
        shareLinkUseCase: ShareSpaceInviteLinkUseCaseProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.space = space
        self.fetchUseCase = fetchUseCase
        self.shareLinkUseCase = shareLinkUseCase
        self.repository = repository
    }

    // MARK: - Computed

    /// Only the owner can invite or remove people — CloudKit enforces this server-side, so
    /// showing the control to a participant would just produce a failure.
    var canInvite: Bool { space.isOwner }

    var joinedCount: Int { members.filter { $0.status == .joined }.count }
    var invitedCount: Int { members.filter { $0.status == .invited }.count }

    var isEmpty: Bool { members.isEmpty && !isLoading }

    /// Drives the full-screen loading indicator. True until the first fetch resolves, and on
    /// any later reload that starts from an empty roster. Because it's true from the very
    /// first frame (before `.task` runs), the spinner shows immediately rather than after a
    /// flash of the empty state — which is what kept the indicator from staying put.
    var showsLoadingState: Bool { !hasLoaded || (isLoading && members.isEmpty) }

    // MARK: - Actions

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        // Mirror our own name into the space before reading the roster, so it's present for
        // everyone (and resolves for us on this very fetch).
        await registerMyDisplayNameIfKnown()
        do {
            members = try await fetchUseCase.execute(for: space)
            errorMessage = nil
        } catch is CancellationError {
            // Cancelled pull-to-refresh — not a real error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persists the chosen display name and reloads, which mirrors it into the space and
    /// re-reads the roster so it reflects the change.
    func saveDisplayName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        myDisplayName = trimmed
        UserDefaults.standard.setSpaceDisplayName(trimmed)
        await load()
    }

    /// Best-effort mirror of the current display name (if set) into the space's zone.
    /// Never surfaces an error — failing to register a name shouldn't break the roster.
    private func registerMyDisplayNameIfKnown() async {
        let trimmed = myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.registerDisplayName(trimmed, in: space)
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

    /// Copies the space's invite link to the pasteboard — the "paste it in a group chat and
    /// anyone can join" path, which needs no named participants up front.
    ///
    /// This is also the point where the space becomes link-joinable: shares are created
    /// invite-only and `ensurePublicInviteLink` opens them on the first call, so it can
    /// take a round trip. `isPreparingLink` covers that.
    func copyInviteLink() async {
        guard canInvite, !isPreparingLink else { return }
        isPreparingLink = true
        defer { isPreparingLink = false }
        do {
            let url = try await shareLinkUseCase.execute(for: space)
            // `.url` rather than `.string` so pasting into Messages/Mail produces a real
            // tappable link; the string form is set too for plain-text destinations.
            UIPasteboard.general.url = url
            UIPasteboard.general.string = url.absoluteString
            didCopyLink = true
            errorMessage = nil
            HapticManager.shared.success()
            scheduleCopiedReset()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    /// Reverts the transient "Link Copied" label after a beat.
    ///
    /// Owned here rather than driven by an `.onChange` in the view: the button lives inside
    /// a `List` `Section`, and `List` destructures its sections, so a modifier hung off the
    /// section is unreliable — it can be dropped or applied once per row. Holding the task
    /// lets a second copy restart the timer cleanly instead of racing the first one's reset.
    private func scheduleCopiedReset() {
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.didCopyLink = false
        }
    }

    /// Called when the sharing controller closes. The participant list may have changed
    /// (invites sent, members removed), so re-read it.
    func inviteSheetDismissed() async {
        shareToPresent = nil
        await load()
    }
}
