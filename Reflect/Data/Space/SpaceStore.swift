import Foundation
import SwiftData

/// The dedicated, isolated SwiftData store for cached Space data. Used to cache
/// CloudKit Spaces, SpaceReflections, and SpaceResponses locally without coupling
/// to the main app's schema or requiring App Group sharing.
/// Kept separate from the main app's ModelContainer so Space data never couples
/// to Reflection/Learning/Insight.
enum SpaceStore {
    /// Builds the Space `ModelContainer` with a tiered, non-fatal fallback.
    ///
    /// The cache MUST NEVER sync to CloudKit — CloudKit is the upstream source of
    /// truth. This container is purely a local mirror for performance and offline
    /// access. A failure to initialize must not crash the app or prevent the Space
    /// UI from rendering; Reflections and Learnings have nothing to do with Space
    /// and must keep working. So instead of `fatalError`, we degrade:
    /// local on-disk store → in-memory store. Only the on-disk tier persists
    /// across launches; the in-memory tier trades durability for stability.
    static let container: ModelContainer = {
        let schema = Schema([CachedSpace.self, CachedSpaceReflection.self, CachedSpaceResponse.self, CachedAnswer.self])

        // A distinct store name ("Space") so this never shares the app's `default.store`.
        let localConfiguration = ModelConfiguration(
            "Space",
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return container
        }
        print("⚠️ SpaceStore: failed to create local on-disk ModelContainer. Falling back to an in-memory store — Space cache will not persist across launches.")

        let memoryConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        // In-memory containers only fail if the schema itself is invalid, which would
        // be a programmer error caught immediately in development, not a runtime
        // condition — so `try!` here does not reintroduce the crash risk we're
        // guarding against above.
        return try! ModelContainer(for: schema, configurations: [memoryConfiguration])
    }()
}
