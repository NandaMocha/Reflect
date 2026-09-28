import Foundation

/// App Group-backed state that lets the full app (`Reflect/App/SpaceInviteInbox.swift`, AC-040)
/// recognize a "Clip-driven install" on its own first cold launch, and lets this Clip know
/// whether it has already shown the `SKOverlay` install upsell once.
///
/// Three independent pieces of state, all mirrored into the same App Group UserDefaults suite
/// (`group.xyz.nandamochammad.Reflect`) `GuestIdentityStore`/`PendingAnswerStore` already use:
///  - **install-overlay-shown flag** — purely Clip-local; read/written only from here, so the
///    `SKOverlay` upsell (`ClipAllFeedbackView`) fires at most once per App Group lifetime (i.e.
///    survives this Clip's own relaunches, not just the current process).
///  - **last request token** — written here, read only by the full app. The full app already has
///    everything else it needs for its own "was this a Clip install?" detection from state other
///    tickets wired: the guest identity via `LiveGuestIdentityStore`'s existing App Group mirror
///    (`clip.guestIdentity`). This token is one of the two missing signals — "did the guest
///    actually reach a resolved request" — so `ClipAllFeedbackViewModel` (only reachable after a
///    token successfully resolved) is the right place to record it.
///  - **has-sent-answer flag** — the other missing signal, "did the guest actually submit
///    something that reached `.sent`." Deliberately *not* derived from `PendingAnswerStore`'s
///    queue file: that file is transient (`dropConfirmedAnswers` prunes `.sent` entries once the
///    mirror confirms them), so by the time the full app's first cold launch checks it, the exact
///    success path this continuity feature targets has usually already emptied it. This flag is
///    written once, durably, the moment a submission first transitions to `.sent`
///    (`ClipYourFeedbackViewModel.submit()`), and isn't affected by anything the queue file does
///    afterward.
protocol ClipInstallContinuityStoring: Sendable {
    /// Whether the install-upsell `SKOverlay` has already been presented once.
    func hasShownInstallOverlay() -> Bool

    /// Marks the install-upsell `SKOverlay` as shown — idempotent, safe to call more than once.
    func markInstallOverlayShown()

    /// Records the most recently resolved `/f/<token>` for the full app's cold-start
    /// install-continuity detection (AC-040). Overwritten on every call — this only needs to
    /// reflect the guest's most recent engaged request, not a history of every one.
    func recordLastRequestToken(_ token: String)

    /// Whether this guest has ever had an answer reach `.sent` — the durable substitute for
    /// re-deriving "has this guest submitted anything" from `PendingAnswerStore`'s transient
    /// queue file (see the type doc comment above). Read by both this Clip (overlay gating) and,
    /// via a matching raw `UserDefaults` key, the full app's `SpaceInviteInbox` (install
    /// continuity).
    func hasEverSentAnswer() -> Bool

    /// Marks that this guest has had at least one answer reach `.sent` — idempotent, safe to call
    /// more than once. Call exactly once per submission batch, right after
    /// `PendingAnswerStore.markSent` confirms at least one `submissionId` was written.
    func recordAnswerSent()
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
    /// Also read by `SpaceInviteInbox.consumeClipDrivenInstall()` via a matching raw literal —
    /// same cross-target convention as `lastRequestTokenKey` above. Written once, durably, the
    /// moment a submission first reaches `.sent` (see the type doc comment) — never derived from
    /// `PendingAnswerStore`'s prunable queue file.
    private let hasSentAnswerKey = "clip.hasSentAnswer"

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

    func hasEverSentAnswer() -> Bool {
        appGroupDefaults?.bool(forKey: hasSentAnswerKey) ?? false
    }

    func recordAnswerSent() {
        appGroupDefaults?.set(true, forKey: hasSentAnswerKey)
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
