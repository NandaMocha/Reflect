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
        case invalidLink
    }

    private(set) var phase: Phase = .loading
    private(set) var requestToken: String?
    private(set) var guestIdentity: GuestIdentity?

    // MARK: - Dependencies

    private let guestIdentityStore: GuestIdentityStoring
    private let logger = Logger(subsystem: "xyz.nandamochammad.Reflect.Clip", category: "ClipSession")

    // MARK: - Initialization

    init(guestIdentityStore: GuestIdentityStoring) {
        self.guestIdentityStore = guestIdentityStore
    }

    // MARK: - Actions

    /// Parses the invocation URL's `requestToken` and moves to `.needsName` or `.compose`
    /// depending on whether a guest identity is already persisted.
    func handle(userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL,
              let token = Self.parseToken(from: url) else {
            phase = .invalidLink
            return
        }
        requestToken = token
        refreshPhaseFromStoredIdentity()
        logger.debug("Parsed requestToken = \(token, privacy: .public)")
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

    /// Called when the root view appears without a resolvable invocation having arrived yet
    /// (e.g. the Clip was relaunched from the App Clip card or app switcher rather than a fresh
    /// `NSUserActivityTypeBrowsingWeb` handoff, or scene restoration). Without this, `.loading`
    /// is a terminal dead end with no route to `.invalidLink` and the root view spins forever.
    /// A no-op once a real invocation has already moved the phase machine past `.loading`.
    func resolveIfIdle() {
        guard phase == .loading else { return }
        phase = .invalidLink
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
