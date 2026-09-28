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
    /// True while one POST of guest answers is in flight, from either the composer
    /// (`ClipYourFeedbackViewModel.submit()`) or `ClipPendingAnswerRetrier`. Both resend the same
    /// stored `submissionId`s and the server keeps whichever copy lands first, so letting them
    /// overlap could drop a guest's edit. Only one may send at a time — see
    /// `beginAnswerDelivery()`.
    private(set) var isAnswerDeliveryInFlight = false
    /// The answers `ClipPendingAnswerRetrier` most recently delivered on its own. The composer
    /// observes this to clear exactly the drafts that went out, instead of the retrier navigating
    /// away from a composer that may hold newer text.
    private(set) var lastAutoDelivery: ClipAutoDelivery?

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

    /// Advances `.compose` -> `.allFeedback` after a confirmed-or-queued submit
    /// (`ClipYourFeedbackViewModel.submit()`). A no-op from any other phase — this is a forward
    /// transition only, never a way to jump into `.allFeedback` from elsewhere.
    func advanceToAllFeedback() {
        guard phase == .compose else { return }
        phase = .allFeedback
    }

    /// Reverse of `advanceToAllFeedback()`: the retry affordance on a `.queued` answer bubble
    /// (`ClipAnswerBubble`) routes back here since there's no in-place retry mechanism yet — the
    /// guest re-submits from the composer, which reuses the same `.queued` `PendingAnswerStore`
    /// entry via `enqueueIfAbsent` rather than double-enqueueing. A no-op from any other phase.
    func returnToCompose() {
        guard phase == .allFeedback else { return }
        phase = .compose
    }

    /// Claims the single answer-delivery slot. Returns `false` when another sender already holds
    /// it; the caller must then skip its POST. Every `true` must be paired with
    /// `endAnswerDelivery()`.
    func beginAnswerDelivery() -> Bool {
        guard !isAnswerDeliveryInFlight else { return false }
        isAnswerDeliveryInFlight = true
        return true
    }

    func endAnswerDelivery() {
        isAnswerDeliveryInFlight = false
    }

    /// Publishes a successful automatic retry for the composer to reconcile. Never changes
    /// `phase` itself.
    func recordAutoDelivery(_ answers: [ClipAutoDelivery.Answer]) {
        guard !answers.isEmpty else { return }
        lastAutoDelivery = ClipAutoDelivery(answers: answers)
    }

    /// Routes to the existing "this link isn't working" phase from anywhere the guest discovers
    /// the request is dead: a `.invalidLink` load failure (`ClipYourFeedbackViewModel.load()`) or
    /// a `.linkRevoked` submit failure (same view model's `submit()`). Reusing `.invalidLink`
    /// rather than adding a separate "revoked mid-session" phase keeps `ClipRootView` a single
    /// switch with one guest-facing copy for "this link no longer works," which is true in both
    /// cases from the guest's point of view.
    func markLinkInvalid() {
        phase = .invalidLink
    }

    /// Renames the current guest **without** minting a new `guestId` — the composer's "Edit name"
    /// affordance (AC-031) uses this instead of `submitDisplayName(_:)` specifically so a rename
    /// mid-session can't orphan answers already submitted under the old `guestId`
    /// (`PendingAnswerStore`/AC-032's dedup key is `guestId`+`questionId`, not display name).
    /// A no-op if no identity exists yet or the trimmed name is empty.
    func updateDisplayName(_ rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var identity = guestIdentity else { return }
        guard trimmed != identity.displayName else { return }

        identity.displayName = trimmed
        do {
            try guestIdentityStore.save(identity)
        } catch {
            logger.error("Failed to persist renamed guest identity — \(String(describing: error), privacy: .public)")
        }
        guestIdentity = identity
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

/// One successful `ClipPendingAnswerRetrier` delivery. `id` makes two deliveries with identical
/// answers still distinct, so `onChange(of:)` fires for each.
struct ClipAutoDelivery: Equatable {
    struct Answer: Equatable {
        let requestToken: String
        let questionId: String
        let body: String
    }

    let id = UUID()
    let answers: [Answer]
}
