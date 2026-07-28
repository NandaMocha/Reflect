import Foundation
import Combine

protocol CloudSyncServiceProtocol {
    var syncStatus: SyncStatus { get }
    var syncStatusPublisher: AnyPublisher<SyncStatus, Never> { get }

    func checkCloudAvailability() async -> CloudAvailability
    func checkExistingData() async throws -> CloudDataSummary?
    func backup(
        learnings: [Learning],
        reflections: [Reflection],
        insights: [CloudInsightRecord]
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

    /// Incrementally upserts learnings and reflections into the private database.
    ///
    /// Records are keyed by a deterministic `CKRecord.ID(recordName: localID)`, so calling this
    /// repeatedly for the same entity overwrites in place (no duplicates) — the write is
    /// idempotent and replay-safe. Unlike `backup()`, it does **not** clear the cloud first.
    /// For each reflection it also reconciles children: server-side attachments for that
    /// reflection that are no longer present locally are deleted, preventing orphans.
    /// Conflict policy is last-push-wins per key (`savePolicy = .changedKeys`).
    func pushUpserts(
        learnings: [CloudLearningRecord],
        reflections: [ReflectionUpsert]
    ) async throws

    /// Deletes entities from the private database, tolerant of already-missing records.
    ///
    /// Deleting a reflection also deletes its child attachment records (matched by
    /// `reflectionID`). Deleting a learning removes only the learning record; reflections that
    /// referenced it are re-pushed separately with a cleared link by the caller.
    func pushDeletes(_ deletions: [SyncDeletion]) async throws

    func deleteAllCloudData() async throws
}
