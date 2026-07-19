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
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Silent pushes need no permission prompt — this just enables the
        // device token registration required to receive them.
        UIApplication.shared.registerForRemoteNotifications()
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
        // TODO(T22): turn this into a real sync trigger. For now, just notify
        // observers that a remote change may be waiting.
        NotificationCenter.default.post(name: .spaceRemoteChangeReceived, object: nil)
        completionHandler(.newData)
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
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        MainActor.assumeIsolated { SpaceInviteInbox.deposit(metadata) }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        MainActor.assumeIsolated { SpaceInviteInbox.deposit(metadata) }
        NotificationCenter.default.post(name: .spaceShareInviteReceived, object: metadata)
    }
}
