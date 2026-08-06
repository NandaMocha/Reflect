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
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
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
    /// Set once a link has been prepared; the view watches this to present the share
    /// sheet. `[Any]` matches `ReflectionShareSheet.items` / `UIActivityViewController`.
    var shareItems: [Any]?
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
            var items: [Any] = [Self.message(for: reflection, url: result.requestLinkURL)]
            if let rawShareURL = result.rawShareURL {
                items.append(rawShareURL)
            }
            shareItems = items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears the staged items once the share sheet has been dismissed, so re-tapping
    /// "Share feedback link" always re-prepares rather than re-presenting stale state.
    func sheetDismissed() {
        shareItems = nil
    }

    private static func message(for reflection: SpaceReflection, url: URL) -> String {
        "Give feedback on \u{201C}\(reflection.title)\u{201D}: \(url.absoluteString)"
    }
}
