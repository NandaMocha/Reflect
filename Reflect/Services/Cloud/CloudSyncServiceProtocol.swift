import Foundation
import Combine

protocol CloudSyncServiceProtocol {
    var syncStatus: SyncStatus { get }
    var syncStatusPublisher: AnyPublisher<SyncStatus, Never> { get }

    func checkCloudAvailability() async -> CloudAvailability
    func checkExistingData() async throws -> CloudDataSummary?
    func backup(
        learnings: [Learning],
        reflections: [Reflection]
    ) async throws -> SyncResult
    /// Downloads the backup and hands it to `apply` for persistence.
    ///
    /// The service owns the network work and the status stream but knows nothing about
    /// SwiftData — writing is the caller's job, which is why it arrives as a `@MainActor`
    /// closure. `apply` returns the number of rows it actually wrote, which becomes
    /// `SyncResult.itemsSynced`. Throwing from `apply` fails the whole restore.
    func restore(
        applying apply: @Sendable @MainActor (CloudBackupSnapshot) throws -> Int
    ) async throws -> SyncResult
    func deleteAllCloudData() async throws
}
