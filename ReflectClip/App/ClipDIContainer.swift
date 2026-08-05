import Foundation

/// The Clip's single dependency-wiring point, mirroring the full app's dependency container
/// (see `Reflect/App/`) but scoped entirely to `ReflectClip/` — no shared instance, no
/// cross-target import.
///
/// **Convention (binding for all later Clip tickets):** feature factories are added via
/// `extension ClipDIContainer` inside the feature's own file — never by editing this file again.
/// This dissolves the serial-lock bottleneck the full app's equivalent file has.
///
/// Intentionally factory-less at this stage; AC-002 fills in `makeGuestIdentityStore()` and
/// session wiring.
@MainActor
final class ClipDIContainer {
    static let shared = ClipDIContainer()

    private init() {}
}
