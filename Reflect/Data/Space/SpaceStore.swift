import Foundation
import SwiftData

/// The dedicated, isolated SwiftData store for cached Space data. Used to cache
/// CloudKit Spaces and SpaceReflections locally without coupling
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
    /// on-disk store → wipe + rebuild the on-disk store → in-memory store.
    /// Only the first two tiers persist across launches; the in-memory tier trades
    /// durability for stability.
    static let container: ModelContainer = {
        let schema = Schema([CachedSpace.self, CachedSpaceReflection.self, CachedAnswer.self])

        // A distinct store name ("Space") so this never shares the app's `default.store`.
        let localConfiguration = ModelConfiguration(
            "Space",
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            // Log the real error. Swallowing it with `try?` hid a schema-break for a
            // whole release cycle and made the eventual crash surface two tiers away
            // from its cause.
            print("⚠️ SpaceStore: on-disk ModelContainer failed to open: \(error)")
        }

        // The cache is disposable by definition — CloudKit is the source of truth and
        // every reader reconciles against it on refresh. So a store we can't open is
        // not a dilemma: delete it and rebuild empty. This is what makes a breaking
        // schema change (e.g. the promptText/Response → questionsJSON/Answer cutover)
        // a one-launch rebuild instead of a boot loop. NEVER apply this pattern to the
        // main `default.store`, which holds the only copy of the user's Reflections.
        destroyLocalStore(at: localConfiguration.url)
        do {
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            print("⚠️ SpaceStore: on-disk ModelContainer still failed after wiping the store: \(error)")
        }

        print("⚠️ SpaceStore: falling back to an in-memory store — Space cache will not persist across launches.")

        let memoryConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            // Required. Without an explicit `.none`, this defaults to `.automatic`,
            // which switches on CloudKit schema validation — and that rejects the
            // cached models outright ("all attributes must be optional or have a
            // default value"), turning the safety net into the crash. The on-disk
            // tiers above set this for the same reason; the memory tier must too.
            cloudKitDatabase: .none
        )
        // With CloudKit validation off, an in-memory container has no disk, no
        // migration and no external validator left to fail on — the remaining failure
        // modes are all compile-time schema errors.
        return try! ModelContainer(for: schema, configurations: [memoryConfiguration])
    }()

    /// Removes the SQLite store and its sidecar journal files. Leaving `-wal`/`-shm`
    /// behind would let a stale write-ahead log resurrect the old schema on reopen.
    private static func destroyLocalStore(at url: URL) {
        let fileManager = FileManager.default
        for path in [url, url.appendingSuffixToLastPathComponent("-wal"), url.appendingSuffixToLastPathComponent("-shm")] {
            do {
                if fileManager.fileExists(atPath: path.path) {
                    try fileManager.removeItem(at: path)
                }
            } catch {
                print("⚠️ SpaceStore: could not delete \(path.lastPathComponent): \(error)")
            }
        }
    }
}

private extension URL {
    /// `Space.store` + `-wal` → `Space.store-wal` (not `Space-wal.store`, which is what
    /// `appendingPathExtension`-style helpers would produce).
    func appendingSuffixToLastPathComponent(_ suffix: String) -> URL {
        deletingLastPathComponent().appending(path: lastPathComponent + suffix)
    }
}
