import Foundation
import SwiftData

/// The dedicated, App-Group-shared SwiftData store for Insights, used by both the
/// main app and the Quick Actions widget extension. Kept separate from the main
/// app's ModelContainer so Insight never couples to Reflection/Learning.
enum InsightStore {
    static let appGroupID = "group.xyz.nandamochammad.Reflect"

    static let container: ModelContainer = {
        let schema = Schema([Insight.self])
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create Insight ModelContainer: \(error)")
        }
    }()
}
