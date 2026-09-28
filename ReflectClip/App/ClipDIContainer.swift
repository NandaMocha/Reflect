import Foundation

/// The Clip's single dependency-wiring point, mirroring the full app's dependency container
/// (see `Reflect/App/`) but scoped entirely to `ReflectClip/` — no shared instance, no
/// cross-target import.
///
/// **Convention (binding for all later Clip tickets):** feature factories are added via
/// `extension ClipDIContainer` inside the feature's own file — never by editing this file again.
/// This dissolves the serial-lock bottleneck the full app's equivalent file has.
///
@MainActor
final class ClipDIContainer {
    static let shared = ClipDIContainer()

    /// The single `ClipSession` instance for the process. `ReflectClipApp` seeds its `@State`
    /// from this, mirroring how the full app wires ViewModels through its own dependency
    /// container's shared instance.
    private(set) lazy var session = ClipSession(guestIdentityStore: makeGuestIdentityStore())

    private init() {}

    // MARK: - Shared Instances

    /// Shared like `session` — the composer screen (`ClipYourFeedbackViewModel`) and the All
    /// Feedback screen (`ClipAllFeedbackViewModel`) must observe the same actor instance's
    /// in-memory state. Before this was a `lazy var`, `makePendingAnswerStore()` minted a fresh
    /// `LivePendingAnswerStore()` per call, so the two screens held independent instances
    /// coordinated only through the shared App Group file — and since `persist()` swallows write
    /// failures, an unresolved container could let a guest submit and immediately see "No
    /// feedback yet," defeating the pending-answer echo this store exists to provide.
    private(set) lazy var sharedPendingAnswerStore: PendingAnswerStoring = LivePendingAnswerStore()

    // MARK: - Factories

    func makeGuestIdentityStore() -> GuestIdentityStoring {
        LiveGuestIdentityStore()
    }
}
