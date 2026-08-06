//
//  AppDelegate.swift
//  Reflect
//
//  UIApplicationDelegate + UIWindowSceneDelegate entry points needed for
//  CloudKit share acceptance and silent-push (remote notification) handling.
//  The app is otherwise pure SwiftUI lifecycle (see ReflectApp.swift) — this
//  adaptor exists solely to catch the two UIKit-only callbacks that SwiftUI's
//  App protocol does not expose:
//    - windowScene(_:userDidAcceptCloudKitShareWith:) on the scene delegate
//    - application(_:didReceiveRemoteNotification:fetchCompletionHandler:) on
//      the app delegate
//
//  IMPORTANT: SwiftUI still owns the window. SceneDelegate must NOT create a
//  UIWindow (e.g. via scene(_:willConnectTo:)) or the app will show a black
//  screen instead of the SwiftUI content.
//

import UIKit
import CloudKit

// MARK: - Notification Names

extension Notification.Name {
    static let spaceShareInviteReceived = Notification.Name("spaceShareInviteReceived")
    static let spaceRemoteChangeReceived = Notification.Name("spaceRemoteChangeReceived")
    /// Posted when a `/f/<token>` guest-feedback request link is opened (AC-014), warm or
    /// cold. Object is the raw token `String`; the actual resolution happens in
    /// `MainTabView` via `ResolveRequestLinkUseCase`, same division of labor as
    /// `spaceShareInviteReceived` above.
    static let spaceRequestLinkReceived = Notification.Name("spaceRequestLinkReceived")
}

// MARK: - Request Link URL Parsing (AC-014)

/// Parses the request token out of a `/f/<token>` URL in either shape this app needs to
/// handle:
///  - the real universal link, `https://nandamochammad.xyz/f/<token>` — "f" is a path
///    component, the host is the domain;
///  - the `reflect://f/<token>` custom-scheme test hook used to verify token resolution
///    in the Simulator via `xcrun simctl openurl` (real AASA-routed universal-link
///    opens can't be driven from the Simulator; that's verified on-device in AC-H4) —
///    "f" is the host, the token is the remaining path.
enum RequestLinkURL {
    static func token(from url: URL) -> String? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if let fIndex = pathComponents.firstIndex(of: "f"), pathComponents.count > fIndex + 1 {
            return nonEmpty(pathComponents[fIndex + 1])
        }
        if url.host == "f", let token = pathComponents.first {
            return nonEmpty(token)
        }
        return nil
    }

    private static func nonEmpty(_ token: String) -> String? {
        token.isEmpty ? nil : token
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register the auto-sync background drain handler. Must happen before launch completes,
        // and the identifier must match Info.plist's BGTaskSchedulerPermittedIdentifiers.
        SyncBackgroundScheduler.register()

        // Silent pushes need no permission prompt — this just enables the
        // device token registration required to receive them.
        UIApplication.shared.registerForRemoteNotifications()

        // Register the Space database subscriptions (idempotent, best-effort — retries
        // next launch if iCloud isn't ready yet).
        Task {
            try? await DIContainer.shared.makeSpaceCloudService().ensureSubscriptions()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // A silent Space push woke us: advance change tokens, then tell any visible Space
        // screen to refresh (which reconciles the cache via the normal fetch path).
        Task {
            let hadChanges = (try? await DIContainer.shared.makeSpaceCloudService().syncChanges()) ?? false
            NotificationCenter.default.post(name: .spaceRemoteChangeReceived, object: nil)
            completionHandler(hadChanges ? .newData : .noData)
        }
    }

    // Belt-and-braces: some launch paths deliver CloudKit share acceptance to
    // the app delegate rather than (or in addition to) the scene delegate.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        MainActor.assumeIsolated { SpaceInviteInbox.deposit(metadata) }
        NotificationCenter.default.post(name: .spaceShareInviteReceived, object: metadata)
    }

    // Belt-and-braces universal-link entry point (AC-014): some warm-launch delivery
    // paths call this on the app delegate rather than (or in addition to)
    // `scene(_:continue:)` below.
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard let token = RequestLinkURL.token(from: userActivity) else { return false }
        MainActor.assumeIsolated { SpaceInviteInbox.depositRequestToken(token) }
        NotificationCenter.default.post(name: .spaceRequestLinkReceived, object: token)
        return true
    }
}

private extension RequestLinkURL {
    /// Convenience for the two `NSUserActivity`-shaped entry points
    /// (`application(_:continue:restorationHandler:)`, `scene(_:continue:)`) — both only
    /// care about `.browsingWeb` activities with a `webpageURL`.
    static func token(from userActivity: NSUserActivity) -> String? {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return nil }
        return token(from: url)
    }
}

// MARK: - SceneDelegate

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    // Cold-launch invite path: when the app is not running and the user taps a share
    // invite, iOS delivers the metadata here via the connection options — before any
    // SwiftUI view exists to receive a notification. We read it and stash it in the inbox
    // for MainTabView to drain on appear.
    //
    // IMPORTANT: this must NOT create or assign a UIWindow — doing so would fight SwiftUI
    // for window ownership and black-screen the app. We only read the connection options.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            MainActor.assumeIsolated { SpaceInviteInbox.deposit(metadata) }
        }
        // Cold-launch request-link open (AC-014): a custom-scheme test URL lands in
        // `urlContexts`, a real universal link lands in `userActivities` — check both,
        // same as the warm-launch handlers below.
        if let token = Self.requestToken(fromColdLaunch: connectionOptions) {
            MainActor.assumeIsolated { SpaceInviteInbox.depositRequestToken(token) }
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        MainActor.assumeIsolated { SpaceInviteInbox.deposit(metadata) }
        NotificationCenter.default.post(name: .spaceShareInviteReceived, object: metadata)
    }

    // Warm-launch custom-scheme open (AC-014's Simulator test hook): `xcrun simctl openurl
    // booted "reflect://f/<token>"` lands here via the `reflect` URL scheme already
    // registered in Info.plist. Real universal-link opens don't come through this method.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url, let token = RequestLinkURL.token(from: url) else { return }
        MainActor.assumeIsolated { SpaceInviteInbox.depositRequestToken(token) }
        NotificationCenter.default.post(name: .spaceRequestLinkReceived, object: token)
    }

    // Warm-launch universal-link open (AC-014): real `/f/<token>` opens routed by iOS via
    // Associated Domains (AASA) land here. Simulator can't drive this path without a
    // signed-in AASA fetch — verified on-device in AC-H4.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let token = RequestLinkURL.token(from: userActivity) else { return }
        MainActor.assumeIsolated { SpaceInviteInbox.depositRequestToken(token) }
        NotificationCenter.default.post(name: .spaceRequestLinkReceived, object: token)
    }

    private static func requestToken(fromColdLaunch connectionOptions: UIScene.ConnectionOptions) -> String? {
        if let url = connectionOptions.urlContexts.first?.url,
           let token = RequestLinkURL.token(from: url) {
            return token
        }
        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }),
           let token = RequestLinkURL.token(from: activity) {
            return token
        }
        return nil
    }
}
