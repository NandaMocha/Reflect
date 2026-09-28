import SwiftUI

/// Entry point for the `ReflectClip` App Clip target.
///
/// Parses the `requestToken` out of the invocation URL
/// (`https://nandamochammad.xyz/f/<token>`), routes through `ClipSession`'s phase machine, and
/// renders `ClipRootView`. `ClipDIContainer.shared` wires the single `ClipSession` instance and
/// its `GuestIdentityStoring` dependency.
///
/// Two delivery paths feed the same token parser, because `.onContinueUserActivity` alone isn't
/// reliable for App Clip invocations on every simulator/iOS combination (confirmed via
/// `launchctl procinfo`: `_XCAppClipURL` was present in the process environment while zero
/// `NSUserActivityTypeBrowsingWeb` continuation ever reached the app):
/// 1. `session.consumeAppClipURLFromEnvironment()` — read directly from `ProcessInfo` at launch.
/// 2. `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` — the normal handoff, when it fires.
/// `ClipSession.startResolutionTimeout()` gives path 2 a window to arrive before the phase
/// machine gives up on `.loading`.
///
/// `ClipPendingAnswerRetrier` re-sends queued (offline) answers whenever the scene becomes active
/// (launch and every foreground), whenever a guest identity resolves (the endpoint needs one), and
/// whenever the request token resolves (queued entries from before `PendingAnswer.requestToken`
/// existed fall back to it). A web-link continuation can deliver either after the first `.active`.
///
/// **Convention (binding for all later Clip tickets):** feature factories are added via
/// `extension ClipDIContainer` inside the feature's own file — never by editing
/// `ClipDIContainer.swift` again.
@main
struct ReflectClipApp: App {
    @State private var session: ClipSession
    @State private var pendingAnswerRetrier: ClipPendingAnswerRetrier
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let session = ClipDIContainer.shared.session
        session.consumeAppClipURLFromEnvironment()
        session.startResolutionTimeout()
        _session = State(initialValue: session)
        _pendingAnswerRetrier = State(initialValue: ClipDIContainer.shared.makeClipPendingAnswerRetrier())
    }

    var body: some Scene {
        WindowGroup {
            ClipRootView(session: session)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    session.handle(userActivity: activity)
                }
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    guard newPhase == .active else { return }
                    pendingAnswerRetrier.retryQueuedAnswers()
                }
                .onChange(of: session.guestIdentity?.guestId) { _, guestId in
                    guard guestId != nil else { return }
                    pendingAnswerRetrier.retryQueuedAnswers()
                }
                .onChange(of: session.requestToken) { _, token in
                    guard token != nil else { return }
                    pendingAnswerRetrier.retryQueuedAnswers()
                }
        }
    }
}
