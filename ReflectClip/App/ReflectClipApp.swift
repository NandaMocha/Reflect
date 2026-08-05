import SwiftUI

/// Entry point for the `ReflectClip` App Clip target.
///
/// Parses the `requestToken` out of the invocation URL
/// (`https://nandamochammad.xyz/f/<token>`) via `NSUserActivityTypeBrowsingWeb`, routes through
/// `ClipSession`'s phase machine, and renders `ClipRootView`. `ClipDIContainer.shared` wires the
/// single `ClipSession` instance and its `GuestIdentityStoring` dependency.
///
/// **Convention (binding for all later Clip tickets):** feature factories are added via
/// `extension ClipDIContainer` inside the feature's own file — never by editing
/// `ClipDIContainer.swift` again.
@main
struct ReflectClipApp: App {
    @State private var session = ClipDIContainer.shared.session

    var body: some Scene {
        WindowGroup {
            ClipRootView(session: session)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    session.handle(userActivity: activity)
                }
        }
    }
}
