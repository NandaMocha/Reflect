import CloudKit

/// Durable hand-off point for an incoming CloudKit share invite, bridging the UIKit
/// scene/app delegates and the SwiftUI `MainTabView`.
///
/// Why this exists: a delegate can receive an invite before `MainTabView` has subscribed
/// to `.spaceShareInviteReceived` — most importantly on a **cold launch**, where the share
/// arrives via `scene(_:willConnectTo:)`'s connection options long before any SwiftUI view
/// appears. A fire-and-forget `NotificationCenter` post would be lost. So the delegate
/// stashes the metadata here and `MainTabView` drains it on appear (it still handles the
/// live notification for the warm case; `drain()` clears the slot so it can't double-process).
///
/// Main-thread only: UIScene / UIApplication delegate callbacks are delivered on the main
/// thread, so `@MainActor` isolation is a natural fit and needs no locking.
@MainActor
enum SpaceInviteInbox {
    private static var pending: CKShare.Metadata?

    /// Stash an invite for `MainTabView` to pick up. A newer invite replaces an unread one.
    static func deposit(_ metadata: CKShare.Metadata) {
        pending = metadata
    }

    /// Returns the stashed invite (if any) and clears the slot, so repeated drains — e.g.
    /// one from the live notification and one from `.task` on first appear — are safe.
    static func drain() -> CKShare.Metadata? {
        defer { pending = nil }
        return pending
    }
}
