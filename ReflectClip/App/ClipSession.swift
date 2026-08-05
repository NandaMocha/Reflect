import Foundation
import Observation
import os

/// The Clip's phase machine: parses the invocation token, resolves (or collects) the guest's
/// identity, and exposes a single `phase` the root view switches on.
@Observable
@MainActor
final class ClipSession {

    // MARK: - State

    enum Phase: Equatable {
        case loading
        case needsName
        case compose
        case allFeedback
        case invocationTimedOut
        case invalidLink
    }

    private(set) var phase: Phase = .loading
    private(set) var requestToken: String?
    private(set) var guestIdentity: GuestIdentity?

    // MARK: - Dependencies

    private let guestIdentityStore: GuestIdentityStoring
    private let logger = Logger(subsystem: "xyz.nandamochammad.Reflect.Clip", category: "ClipSession")
    private var resolutionTimeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    init(guestIdentityStore: GuestIdentityStoring) {
        self.guestIdentityStore = guestIdentityStore
    }

    // MARK: - Actions

    /// Parses the invocation URL's `requestToken` and moves to `.needsName` or `.compose`
    /// depending on whether a guest identity is already persisted.
    func handle(userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else {
            phase = .invalidLink
            return
        }
        handle(url: url)
    }

    /// Reads `_XCAppClipURL` directly from the process environment and, if present, handles it
    /// exactly like a delivered `NSUserActivityTypeBrowsingWeb` continuation.
    ///
    /// This is a fallback, not a replacement: on some simulator/iOS combinations `_XCAppClipURL`
    /// is confirmed present in the launched process's environment (via `launchctl procinfo`) yet
    /// `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` never fires — zero continuation
    /// reaches the app and the guest sees a false "this link isn't working". Reading the env var
    /// directly is exactly what it's documented for, so the phase machine stays reachable
    /// regardless of which delivery path actually fires. A no-op once a real invocation (from
    /// either path) has already moved the phase machine past `.loading`.
    func consumeAppClipURLFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard phase == .loading, requestToken == nil else { return }
        guard let raw = environment["_XCAppClipURL"], let url = URL(string: raw) else { return }
        handle(url: url)
    }

    private func handle(url: URL) {
        guard let token = Self.parseToken(from: url) else {
            phase = .invalidLink
            return
        }
        requestToken = token
        refreshPhaseFromStoredIdentity()
        #if DEBUG
        logger.debug("Parsed requestToken = \(token, privacy: .private)")
        #endif
    }

    /// Called by the `.needsName` screen once the guest submits a display name. Mints a new
    /// `guestId`, persists it, and advances to `.compose`. A persistence failure is logged but
    /// never strands the guest — the identity still lives in memory for this session.
    func submitDisplayName(_ rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let identity = GuestIdentity(guestId: UUID(), displayName: trimmed)
        do {
            try guestIdentityStore.save(identity)
        } catch {
            logger.error("Failed to persist guest identity — \(String(describing: error), privacy: .public)")
        }
        guestIdentity = identity
        phase = .compose
    }

    /// Starts (or restarts) the timeout that gives up on `.loading` after `seconds` with no
    /// invocation having arrived (e.g. the Clip was relaunched from the App Clip card or app
    /// switcher rather than a fresh `NSUserActivityTypeBrowsingWeb` handoff, or scene
    /// restoration, or the environment-fallback lookup also found nothing). Without this,
    /// `.loading` is a terminal dead end with no way out and the root view spins forever.
    ///
    /// Lives here rather than inline in the view's `.task()`/`.onAppear()` so the timing is
    /// testable and decoupled from view lifecycle — call from `ReflectClipApp` once at launch.
    func startResolutionTimeout(after seconds: Duration = .seconds(2)) {
        resolutionTimeoutTask?.cancel()
        resolutionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: seconds)
            guard !Task.isCancelled else { return }
            self?.resolveIfIdle()
        }
    }

    /// "The invocation hasn't arrived yet" and "this is a genuinely bad/revoked link" are
    /// different failure modes with different guest-facing meaning, so a timeout lands on its
    /// own `.invocationTimedOut` phase rather than reusing `.invalidLink` — only a token that
    /// actually failed to parse (or a link the server rejects later) is a "bad link".
    /// A no-op once a real invocation has already moved the phase machine past `.loading`.
    func resolveIfIdle() {
        guard phase == .loading else { return }
        phase = .invocationTimedOut
    }

    /// Retry affordance from the `.invocationTimedOut` screen: gives the environment fallback and
    /// a fresh continuation another window to arrive before timing out again.
    func retryResolution() {
        guard phase == .invocationTimedOut else { return }
        phase = .loading
        consumeAppClipURLFromEnvironment()
        startResolutionTimeout()
    }

    // MARK: - Private Helpers

    private func refreshPhaseFromStoredIdentity() {
        if let stored = guestIdentityStore.loadIdentity() {
            guestIdentity = stored
            phase = .compose
        } else {
            phase = .needsName
        }
    }

    /// Expects `https://nandamochammad.xyz/f/<token>`.
    private static func parseToken(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "f", !components[1].isEmpty else {
            return nil
        }
        return components[1]
    }
}
