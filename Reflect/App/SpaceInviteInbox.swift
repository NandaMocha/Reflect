import CloudKit
import os

/// Durable hand-off point for an incoming CloudKit share invite, bridging the UIKit
/// scene/app delegates and the SwiftUI `MainTabView`.
///
/// Why this exists: a delegate can receive an invite before `MainTabView` has subscribed
/// to `.spaceShareInviteReceived` — most importantly on a **cold launch**, where the share
/// arrives via `scene(_:willConnectTo:)`'s connection options long before any SwiftUI view
/// appears. A fire-and-forget `NotificationCenter` post would be lost. So the delegate
/// stashes the metadata here and `MainTabView` drains it on appear (it still handles the
/// live notification for the warm case; `drain()` clears the slot so it can't double-process).
///
/// Main-thread only: UIScene / UIApplication delegate callbacks are delivered on the main
/// thread, so `@MainActor` isolation is a natural fit and needs no locking.
@MainActor
enum SpaceInviteInbox {
    private static var pending: CKShare.Metadata?

    /// Stash an invite for `MainTabView` to pick up. A newer invite replaces an unread one.
    static func deposit(_ metadata: CKShare.Metadata) {
        pending = metadata
    }

    /// Returns the stashed invite (if any) and clears the slot, so repeated drains — e.g.
    /// one from the live notification and one from `.task` on first appear — are safe.
    static func drain() -> CKShare.Metadata? {
        defer { pending = nil }
        return pending
    }

    // MARK: - AC-014: guest-feedback request links (`/f/<token>`)

    /// Same hand-off problem as `pending` above, one step earlier: resolving a `/f/<token>`
    /// open into a `CKShare` is async network work (`SpaceRequestLinkService`) the
    /// delegate can't do inline, so it stashes just the raw token here and `MainTabView`
    /// resolves + navigates once the presentation stack is settled.
    private static var pendingRequestToken: String?

    /// Stash a request-link token for `MainTabView` to resolve. A newer link replaces an
    /// unread one, same policy as `deposit(_:)`.
    static func depositRequestToken(_ token: String) {
        pendingRequestToken = token
    }

    /// Returns the stashed token (if any) and clears the slot.
    static func drainRequestToken() -> String? {
        defer { pendingRequestToken = nil }
        return pendingRequestToken
    }

    // MARK: - AC-040: Clip-driven install continuity

    private static let logger = Logger(subsystem: "xyz.nandamochammad.Reflect", category: "SpaceInviteInbox")

    /// The App Group `ReflectClip` and this app share — same value as the literal constants in
    /// `ReflectClip/Data/GuestIdentityStore.swift` and
    /// `ReflectClip/Features/AllFeedback/ClipInstallContinuityStore.swift` (kept independent here
    /// rather than centralized, matching this codebase's existing convention of not sharing that
    /// constant across those files either).
    private static let appGroupIdentifier = "group.xyz.nandamochammad.Reflect"
    /// Matches `LiveGuestIdentityStore`'s `appGroupDefaultsKey` exactly — this reads the same
    /// mirror record the Clip already writes on every `submitDisplayName`/`updateDisplayName`, so
    /// no new Clip-side write was needed for guest identity.
    private static let guestIdentityDefaultsKey = "clip.guestIdentity"
    /// Matches `LiveClipInstallContinuityStore`'s `lastRequestTokenKey`
    /// (`ReflectClip/Features/AllFeedback/ClipInstallContinuityStore.swift`) exactly.
    private static let lastRequestTokenDefaultsKey = "clip.lastRequestToken"
    /// Matches `LiveClipInstallContinuityStore`'s `hasSentAnswerKey` exactly. Durable — written
    /// once, at successful-submit time, by `ClipYourFeedbackViewModel.submit()` via
    /// `ClipInstallContinuityStoring.recordAnswerSent()`. Deliberately **not** derived from
    /// `LivePendingAnswerStore`'s queue file (`clip-pending-answers.json`): that file is transient
    /// by design — `dropConfirmedAnswers` prunes `.sent` entries the moment the mirror confirms
    /// them, which the Clip does on every successful "All feedback" fetch. Reading the queue file
    /// here would mean the exact success path this feature exists to detect (guest submits →
    /// ingestion posts → Clip refetches → file empties) reliably destroys the signal before this
    /// full-app cold launch ever gets a chance to read it. See a prior review of this file for the
    /// full account of that bug.
    private static let hasSentAnswerDefaultsKey = "clip.hasSentAnswer"

    /// Mirrors the JSON shape of `ReflectClip/Data/GuestIdentityStore.swift`'s `GuestIdentity` —
    /// that type itself isn't shared into this target (it isn't under `Reflect/ClipShared/`), so
    /// this only decodes the two fields actually needed here rather than pulling in the whole
    /// type via a new cross-target file for one read site.
    private struct MirroredGuestIdentity: Decodable {
        let displayName: String
    }

    /// One-shot detection for "this full-app launch looks like it followed a Clip-driven
    /// install" — called from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// All three signals AC-040 specifies have to agree, each independently written by Clip-side
    /// code that already exists for other reasons:
    ///  - a guest identity the Clip persisted (mirrored into the App Group by
    ///    `LiveGuestIdentityStore` on every guest-identity save),
    ///  - a durable "this guest had an answer reach `.sent`" flag
    ///    (`LiveClipInstallContinuityStore.recordAnswerSent()`, written once at submit time — see
    ///    `hasSentAnswerDefaultsKey`'s doc comment for why this isn't read from the pending-answer
    ///    queue file instead),
    ///  - a `/f/<token>` the guest actually reached the "All feedback" screen for
    ///    (`LiveClipInstallContinuityStore.recordLastRequestToken(_:)`).
    /// Any one being absent means either no Clip was ever involved on this device, or the guest
    /// opened a link but never got as far as submitting — neither should auto-resolve.
    ///
    /// Consumes (clears) both the last-token and has-sent-answer signals on a match so this can
    /// never fire twice for the same install: a later ordinary `/f/<token>` open still resolves
    /// normally through `depositRequestToken(_:)` (the AASA/custom-scheme paths below), it just
    /// won't be mistaken for a fresh Clip handoff again on a future cold launch.
    static func consumeClipDrivenInstall() -> (token: String, guestDisplayName: String?)? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }

        guard let token = defaults.string(forKey: lastRequestTokenDefaultsKey), !token.isEmpty else {
            return nil
        }
        guard let identityData = defaults.data(forKey: guestIdentityDefaultsKey) else {
            return nil
        }
        guard let identity = try? JSONDecoder().decode(MirroredGuestIdentity.self, from: identityData) else {
            logger.error("Mirrored guest identity present but failed to decode as MirroredGuestIdentity — Clip-side GuestIdentity encoding may have changed")
            return nil
        }
        guard defaults.bool(forKey: hasSentAnswerDefaultsKey) else { return nil }

        defaults.removeObject(forKey: lastRequestTokenDefaultsKey)
        defaults.removeObject(forKey: hasSentAnswerDefaultsKey)

        let trimmedName = identity.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token, trimmedName.isEmpty ? nil : trimmedName)
    }
}
