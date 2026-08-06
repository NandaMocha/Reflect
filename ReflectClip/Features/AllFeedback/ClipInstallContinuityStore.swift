import Foundation

/// App Group-backed state that lets the full app (`Reflect/App/SpaceInviteInbox.swift`, AC-040)
/// recognize a "Clip-driven install" on its own first cold launch, and lets this Clip know
/// whether it has already shown the `SKOverlay` install upsell once.
///
/// Two independent pieces of state, both mirrored into the same App Group UserDefaults suite
/// (`group.xyz.nandamochammad.Reflect`) `GuestIdentityStore`/`PendingAnswerStore` already use:
///  - **install-overlay-shown flag** — purely Clip-local; read/written only from here, so the
///    `SKOverlay` upsell (`ClipAllFeedbackView`) fires at most once per App Group lifetime (i.e.
///    survives this Clip's own relaunches, not just the current process).
///  - **last request token** — written here, read only by the full app. The full app already has
///    everything else it needs for its own "was this a Clip install?" detection from state other
///    tickets wired: the guest identity via `LiveGuestIdentityStore`'s existing App Group mirror
///    (`clip.guestIdentity`), and "has this guest actually submitted anything" via
///    `LivePendingAnswerStore`'s existing file. This token is the one missing signal — "did the
///    guest actually reach a resolved request" — so `ClipAllFeedbackViewModel` (only reachable
///    after a token successfully resolved) is the right place to record it.
protocol ClipInstallContinuityStoring: Sendable {
    /// Whether the install-upsell `SKOverlay` has already been presented once.
    func hasShownInstallOverlay() -> Bool

    /// Marks the install-upsell `SKOverlay` as shown — idempotent, safe to call more than once.
    func markInstallOverlayShown()

    /// Records the most recently resolved `/f/<token>` for the full app's cold-start
    /// install-continuity detection (AC-040). Overwritten on every call — this only needs to
    /// reflect the guest's most recent engaged request, not a history of every one.
    func recordLastRequestToken(_ token: String)
}

/// Stateless beyond its constants (same shape as `LiveGuestIdentityStore`), so it's safely
/// `Sendable` without `@unchecked` — every stored property is an immutable `Sendable` value and
/// `UserDefaults` itself is thread-safe.
final class LiveClipInstallContinuityStore: ClipInstallContinuityStoring, Sendable {

    // MARK: - Constants

    private let appGroupIdentifier = "group.xyz.nandamochammad.Reflect"
    private let installOverlayShownKey = "clip.installOverlayShown"
    /// Read by `Reflect/App/SpaceInviteInbox.swift`'s `consumeClipDrivenInstall()` — the two
    /// key strings must match exactly (kept as independent literals rather than a shared
    /// constant, matching this codebase's existing convention of not centralizing the App
    /// Group identifier itself across `GuestIdentityStore`/`PendingAnswerStore`).
    private let lastRequestTokenKey = "clip.lastRequestToken"

    // MARK: - Initialization

    init() {}

    // MARK: - ClipInstallContinuityStoring

    func hasShownInstallOverlay() -> Bool {
        appGroupDefaults?.bool(forKey: installOverlayShownKey) ?? false
    }

    func markInstallOverlayShown() {
        appGroupDefaults?.set(true, forKey: installOverlayShownKey)
    }

    func recordLastRequestToken(_ token: String) {
        appGroupDefaults?.set(token, forKey: lastRequestTokenKey)
    }

    // MARK: - Private Helpers

    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}

// MARK: - DIContainer Factory

extension ClipDIContainer {
    func makeClipInstallContinuityStore() -> ClipInstallContinuityStoring {
        LiveClipInstallContinuityStore()
    }
}
