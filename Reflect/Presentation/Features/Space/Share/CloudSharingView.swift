import SwiftUI
import CloudKit
import UIKit
import Observation

/// Presents the system CloudKit share sheet (`UICloudSharingController`) for an
/// already-saved `CKShare`. Also doubles as the owner's participant-management
/// and stop-sharing UI, since `UICloudSharingController` provides that for free.
///
/// - Important: This wrapper always uses the existing-share initializer
///   (`UICloudSharingController(share:container:)`), never the `prepareHandler`
///   variant, so it never creates a share lazily — the share must already exist.
struct CloudSharingView: UIViewControllerRepresentable {

    // MARK: - Inputs

    let share: CKShare
    let container: CKContainer
    let spaceName: String
    var onSaved: (() -> Void)? = nil
    var onStopped: (() -> Void)? = nil
    var onError: ((Error) -> Void)? = nil

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // `.allowPublic` is load-bearing, not just an extra option: the controller writes its
        // own permission selection back to the share on save, and if only `.allowPrivate` is
        // offered it resets `publicPermission` to `.none` — silently killing every invite
        // link the owner has already pasted somewhere. `.allowPrivate` stays available so an
        // owner can still deliberately re-lock a space to named participants only.
        controller.availablePermissions = [.allowReadWrite, .allowPublic, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: CloudSharingView

        init(_ parent: CloudSharingView) {
            self.parent = parent
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.spaceName
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            parent.onError?(error)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            parent.onSaved?()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStopped?()
        }
    }
}

// MARK: - Request Link Share Presenter (AC-014)

/// The "share a single feedback request" entry point — distinct from `CloudSharingView`
/// above, which wraps `UICloudSharingController` for whole-Space membership invites (see
/// `SpaceFormView`/`SpaceMembersView`). A guest-feedback request link doesn't need
/// CloudKit's native participant-management UI: it's a plain URL a guest opens (via the
/// App Clip or the full app's universal-link handling), so a system
/// `UIActivityViewController` is enough. This presenter mints/reuses the link
/// (`ShareFeedbackRequestUseCase`) and stages the resulting text for `ReflectionShareSheet`.
@Observable
@MainActor
final class RequestLinkSharePresenter {
    var isPreparing = false
    /// Set once a link has been prepared; the view drives `sheet(item:)` off this so the
    /// optional is unwrapped safely instead of an `isPresented` boolean the view has to
    /// keep in sync by hand.
    var shareItems: ShareItems?
    var errorMessage: String?

    private let useCase: ShareFeedbackRequestUseCaseProtocol

    init(useCase: ShareFeedbackRequestUseCaseProtocol) {
        self.useCase = useCase
    }

    /// Mints/reuses the request token, triggers a mirror publish, and stages the wrapper
    /// URL — alongside the space's raw `CKShare` URL when it's available — for the system
    /// share sheet.
    func prepare(reflection: SpaceReflection, space: Space) async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let result = try await useCase.execute(reflection: reflection, space: space)
            // Still shares only the `/f/<token>` wrapper link, not `result.rawShareURL` —
            // but for a different reason than before. The original blocker (the Space's
            // `CKShare` was `publicPermission = .none`, so its raw URL only resolved for
            // Apple IDs already on the participant list) is gone: shares are now created
            // public, and `SpaceCloudService.ensurePublicInviteLink` migrates older ones.
            //
            // The remaining reason is scope. The raw `CKShare` URL joins the recipient to
            // the whole Space, while a `/f/<token>` link is meant to point at one feedback
            // request. Sending both would quietly turn "give feedback on this" into full
            // Space membership. The Space-wide link now has its own deliberate entry point
            // (Members → "Copy Invite Link"), which is where that choice belongs.
            shareItems = ShareItems(values: [Self.message(for: reflection, url: result.requestLinkURL)])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func message(for reflection: SpaceReflection, url: URL) -> String {
        "Give feedback on \u{201C}\(reflection.title)\u{201D}: \(url.absoluteString)"
    }

    /// `Identifiable` wrapper around the raw `[Any]` activity-item list `sheet(item:)`
    /// needs — `[Any]` itself has no stable identity to key the presentation off of.
    struct ShareItems: Identifiable {
        let id = UUID()
        let values: [Any]
    }
}
