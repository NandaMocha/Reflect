import Foundation
import SwiftData

/// The dedicated, App-Group-shared SwiftData store for Insights, used by both the
/// main app and the Quick Actions widget extension. Kept separate from the main
/// app's ModelContainer so Insight never couples to Reflection/Learning.
enum InsightStore {
    static let appGroupID = "group.xyz.nandamochammad.Reflect"

    /// Builds the Insight `ModelContainer` with a tiered, non-fatal fallback.
    ///
    /// `TabView` constructs both tabs' content eagerly, so this is force-evaluated
    /// at every app launch via `.modelContainer(InsightStore.container)` on the
    /// Insights tab. A failure here must never crash the whole app — Learnings and
    /// Reflections have nothing to do with Insight and must keep working even if the
    /// App Group entitlement isn't honored (e.g. not yet provisioned on device).
    /// So instead of `fatalError`, we degrade: shared App-Group store → local on-disk
    /// store → in-memory store. Only the App-Group tier loses cross-process sharing
    /// with the widget/App Intent; the in-memory tier loses persistence, but the
    /// Insights tab still renders instead of taking the app down with it.
    static let container: ModelContainer = {
        let schema = Schema([Insight.self])

        // A distinct store name ("Insight.store") so this never shares the App Group's
        // `default.store` with the main app's container.
        let appGroupConfiguration = ModelConfiguration(
            "Insight",
            schema: schema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [appGroupConfiguration]) {
            return container
        }
        print("⚠️ InsightStore: failed to create App-Group ModelContainer (group: \(appGroupID)). Falling back to a local on-disk store — Insights will not sync with the widget/App Intent.")

        let localConfiguration = ModelConfiguration(
            "Insight",
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return container
        }
        print("⚠️ InsightStore: failed to create local on-disk ModelContainer. Falling back to an in-memory store — Insights will not persist across launches.")

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
