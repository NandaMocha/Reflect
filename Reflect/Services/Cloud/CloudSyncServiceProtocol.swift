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
    func restore() async throws -> SyncResult
    func deleteAllCloudData() async throws
}
