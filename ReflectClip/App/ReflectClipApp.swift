import SwiftUI

/// Entry point for the `ReflectClip` App Clip target.
///
/// Parses the `requestToken` out of the invocation URL
/// (`https://nandamochammad.xyz/f/<token>`) via `NSUserActivityTypeBrowsingWeb` and logs it.
/// `ClipSession` here is a deliberately small stub — AC-002 replaces it with the full
/// `App/ClipSession.swift` (guest identity, phase machine) per the task breakdown's file lock
/// (`ReflectClip/App/ReflectClipApp.swift`: AC-001 → AC-002).
@main
struct ReflectClipApp: App {
    @State private var session = ClipSession()

    var body: some Scene {
        WindowGroup {
            ClipScaffoldPlaceholderView(session: session)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    session.handle(userActivity: activity)
                }
        }
    }
}

/// Minimal `@Observable` stub for the parsed invocation state. Intentionally thin — full guest
/// identity + phase gating lands in AC-002.
@Observable
@MainActor
final class ClipSession {

    // MARK: - State

    enum Phase {
        case loading
        case needsName
        case compose
        case allFeedback
        case invalidLink
    }

    private(set) var phase: Phase = .loading
    private(set) var requestToken: String?

    // MARK: - Actions

    func handle(userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL,
              let token = Self.parseToken(from: url) else {
            phase = .invalidLink
            return
        }
        requestToken = token
        phase = .needsName
        #if DEBUG
        print("ReflectClip: parsed requestToken = \(token)")
        #endif
    }

    // MARK: - Private Helpers

    /// Expects `https://nandamochammad.xyz/f/<token>`.
    private static func parseToken(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "f", !components[1].isEmpty else {
            return nil
        }
        return components[1]
    }
}

/// Scaffolding-only placeholder screen. Replaced by `ClipRootView` (AC-002) once the phase
/// machine and guest identity flow exist.
private struct ClipScaffoldPlaceholderView: View {
    let session: ClipSession

    var body: some View {
        VStack(spacing: Constants.Spacing.md) {
            Text("Reflect Clip")
                .font(.title2.bold())
                .foregroundStyle(.tint)
            Text("Scaffolding placeholder — the real composer lands in later tickets.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let token = session.requestToken {
                Text("Token: \(token)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }
}
