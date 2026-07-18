import SwiftUI
import CloudKit
import UIKit

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
