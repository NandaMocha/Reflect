import Foundation
import Observation

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
        #if DEBUG
        print("ReflectClip: parsed requestToken = \(token)")
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
            #if DEBUG
            print("ReflectClip: failed to persist guest identity — \(error)")
            #endif
        }
        guestIdentity = identity
        phase = .compose
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
