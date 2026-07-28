import Foundation
import Observation
import SwiftData

/// Drives incremental auto-sync: repositories enqueue `PendingSyncOp` rows as part of their own
/// `context.save()`, and this coordinator debounces, coalesces, and drains them to the private
/// CloudKit database via `CloudSyncService`'s push API.
///
/// Lives for the app's lifetime as a single shared instance (`DIContainer.makeSyncCoordinator`).
/// `@MainActor` because it reads the live SwiftData graph (mapping `@Model` → Sendable DTOs) on
/// the main context before handing the Sendable payload to the off-actor network work.
@MainActor
@Observable
final class SyncCoordinator {

    // MARK: - State

    enum State: Equatable {
        case idle
        case syncing
        case offline
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var pendingCount: Int = 0

    /// True while `enableAndReconcile()`'s one-time full re-key backup is running (Task 6).
    /// Settings (Task 7) shows this instead of the regular `state` copy while it's set.
    private(set) var isReconciling: Bool = false

    /// Wall-clock time of the last successful drain or reconcile, for Settings' "Last synced" row.
    private(set) var lastSyncedAt: Date?

    /// Master switch (Settings toggle, Task 7). Defaults off until the feature fully lands.
    /// Stored (not computed over UserDefaults) so `@Observable` tracks it and the Settings
    /// toggle re-renders on change; `didSet` mirrors it to UserDefaults for persistence.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    static let enabledKey = "autoSyncEnabled"

    // MARK: - Dependencies

    private let cloudSyncService: CloudSyncServiceProtocol
    private let modelContext: ModelContext

    // MARK: - Tuning (injectable so a future test suite can drive drains deterministically)

    var debounce: Duration = .seconds(3)
    private let maxAttempts = 5
    private let maxBackoffSeconds: Double = 60

    // MARK: - Private

    private var drainTask: Task<Void, Never>?

    /// Guards against overlapping drains: `@MainActor` is reentrant, so a scheduled drain and a
    /// lifecycle-triggered drain can interleave across an `await`. Without this they'd fetch the
    /// same ops, double-push, and double-delete the same rows.
    private var isDraining = false
    private var drainRequestedWhileBusy = false

    /// Depth counters (not a single bool) so overlapping brackets — e.g. a lifecycle drain and
    /// a manual backup — don't have one `endPause` un-pausing the other's bracket. Draining and
    /// enqueueing are suppressed independently: restore/seed must suppress both (imported rows
    /// are cloud echoes, not new intent), but a manual backup should keep enqueueing user edits
    /// made mid-backup — just not drain them until the backup itself finishes.
    private var drainPauseDepth = 0
    private var enqueueSuppressDepth = 0

    var isDrainPaused: Bool { drainPauseDepth > 0 }

    // MARK: - Initialization

    init(cloudSyncService: CloudSyncServiceProtocol, modelContext: ModelContext) {
        self.cloudSyncService = cloudSyncService
        self.modelContext = modelContext
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        refreshPendingCount()
    }

    // MARK: - Enqueue
    //
    // Called by repositories BEFORE their own `context.save()`. The op is inserted into the
    // shared context but NOT saved here, so the caller's single save() commits the entity
    // mutation and its sync intent atomically — no window where one exists without the other.

    func enqueueUpsert(_ entityType: PendingSyncOp.EntityType, id: UUID) {
        enqueue(entityType, id: id, op: .upsert)
    }

    func enqueueDelete(_ entityType: PendingSyncOp.EntityType, id: UUID) {
        enqueue(entityType, id: id, op: .delete)
    }

    private func enqueue(_ entityType: PendingSyncOp.EntityType, id: UUID, op: PendingSyncOp.Operation) {
        guard isEnabled, enqueueSuppressDepth == 0 else { return }
        modelContext.insert(PendingSyncOp(entityType: entityType, entityID: id, op: op))
        pendingCount += 1  // optimistic; reconciled on the next drain
        scheduleDrain()
    }

    // MARK: - Scheduling

    /// Debounced drain: bursts of edits coalesce into a single drain after `debounce`.
    func scheduleDrain() {
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            await self.drain()
        }
    }

    // MARK: - Drain

    /// Pushes all pending ops now (bypassing the debounce). Safe to call from lifecycle events.
    func drain() async {
        guard isEnabled, drainPauseDepth == 0 else { return }

        // Coalesce overlapping drains: if one is already in flight, ask it to run once more when
        // it finishes rather than racing it.
        guard !isDraining else {
            drainRequestedWhileBusy = true
            return
        }
        isDraining = true
        defer {
            isDraining = false
            if drainRequestedWhileBusy {
                drainRequestedWhileBusy = false
                scheduleDrain()
            }
        }

        guard await cloudSyncService.checkCloudAvailability() == .available else {
            state = .offline
            return
        }

        let ops = fetchPendingOps()
        guard !ops.isEmpty else {
            state = .idle
            pendingCount = 0
            return
        }

        state = .syncing

        // Map each entity's latest intent to a Sendable payload on the main actor.
        var learningUpserts: [CloudLearningRecord] = []
        var reflectionUpserts: [ReflectionUpsert] = []
        var deletions: [SyncDeletion] = []

        for (key, latestOp) in coalesce(ops) {
            switch (key.type, latestOp.operationValue) {
            case (.learning, .upsert):
                if let learning = fetchLearning(id: key.id) {
                    learningUpserts.append(CloudLearningRecord(from: learning))
                } else {
                    // Gone locally before the drain — push a delete instead of a stale upsert.
                    deletions.append(SyncDeletion(entityType: .learning, entityID: key.id))
                }
            case (.reflection, .upsert):
                if let reflection = fetchReflection(id: key.id) {
                    reflectionUpserts.append(ReflectionUpsert(from: reflection))
                } else {
                    deletions.append(SyncDeletion(entityType: .reflection, entityID: key.id))
                }
            case (.learning, .delete):
                deletions.append(SyncDeletion(entityType: .learning, entityID: key.id))
            case (.reflection, .delete):
                deletions.append(SyncDeletion(entityType: .reflection, entityID: key.id))
            case (_, .none):
                break  // unrecognized op string — skip, it'll be cleared with the batch
            }
        }

        do {
            if !learningUpserts.isEmpty || !reflectionUpserts.isEmpty {
                try await cloudSyncService.pushUpserts(learnings: learningUpserts, reflections: reflectionUpserts)
            }
            if !deletions.isEmpty {
                try await cloudSyncService.pushDeletes(deletions)
            }

            // Success: remove every drained op row.
            for op in ops { modelContext.delete(op) }
            try? modelContext.save()
            refreshPendingCount()

            if pendingCount > 0 {
                // Edits landed during the push — drain them too.
                state = .syncing
                scheduleDrain()
            } else {
                state = .idle
                lastSyncedAt = Date()
            }
        } catch {
            handleDrainFailure(ops: ops, error: error)
        }
    }

    /// Waits for a drain already in flight (started by a debounce or a lifecycle event) to
    /// finish, so a caller that's about to pause drains starts from a clean state. Bounded by
    /// `timeout` and cancellation-aware so a stuck or cancelled drain can't hang the caller
    /// forever.
    func awaitInFlightDrain(timeout: Duration = .seconds(30)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while isDraining {
            if ContinuousClock.now >= deadline { break }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { break } // cancelled -> stop
        }
    }

    // MARK: - Pause API
    //
    // Depth-counted so overlapping brackets compose safely. Always balance a `beginPause` with
    // an `endPause` using the SAME `suppressEnqueue` value.

    /// Pauses drains (and optionally enqueueing) around an exclusive op, first awaiting any
    /// drain already in flight so the caller starts clean.
    func beginPause(suppressEnqueue: Bool) async {
        drainPauseDepth += 1
        if suppressEnqueue { enqueueSuppressDepth += 1 }
        await awaitInFlightDrain()
    }

    func endPause(suppressEnqueue: Bool) {
        drainPauseDepth = max(0, drainPauseDepth - 1)
        if suppressEnqueue { enqueueSuppressDepth = max(0, enqueueSuppressDepth - 1) }
    }

    // MARK: - First-enable reconcile (Task 6)

    /// Turns auto-sync on for a device that may already have cloud data pushed under the old
    /// random-recordName scheme (pre deterministic IDs). Runs one full `backup()` — which now
    /// writes deterministic `CKRecord.ID`s — to re-key that data, then switches on incremental
    /// sync. Paused for the duration so the backup's own writes don't also enqueue incremental
    /// ops; on success, any ops it superseded are cleared since the backup already covers them.
    ///
    /// Leaves `isEnabled` false if the reconcile fails, so a failed first-enable doesn't leave
    /// the toggle silently on with stale un-rekeyed cloud data.
    func enableAndReconcile() async throws {
        guard !isReconciling else { return }     // reentrancy guard (synchronous, before any await)
        isReconciling = true
        state = .syncing
        defer { isReconciling = false }

        guard await cloudSyncService.checkCloudAvailability() == .available else {
            state = .offline
            throw SyncCoordinatorError.cloudUnavailable
        }

        await beginPause(suppressEnqueue: false)   // pauses drains + awaits in-flight drain
        defer { endPause(suppressEnqueue: false) }

        let learnings = fetchAllLearnings()
        let reflections = fetchAllReflections()

        do {
            // This reconcile path only re-keys Learnings/Reflections onto deterministic
            // CKRecord.IDs (Task 6); it predates Insight and isn't part of Insight's manual
            // backup/restore flow, so it passes no insights here.
            let result = try await cloudSyncService.backup(learnings: learnings, reflections: reflections, insights: [])
            guard result.success else {
                let message = "Reconcile completed with \(result.errors.count) error(s)"
                state = .failed(message)
                throw SyncCoordinatorError.reconcileFailed(message)
            }

            // The full backup just re-uploaded everything it covers; drop any ops it superseded
            // rather than re-pushing them incrementally right after.
            for op in fetchPendingOps() { modelContext.delete(op) }
            try? modelContext.save()
            refreshPendingCount()

            isEnabled = true
            state = .idle
            lastSyncedAt = Date()
        } catch let error as SyncCoordinatorError {
            throw error
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func handleDrainFailure(ops: [PendingSyncOp], error: Error) {
        for op in ops {
            op.attemptCount += 1
            op.lastError = error.localizedDescription
        }
        try? modelContext.save()
        state = .failed(error.localizedDescription)

        let maxAttempt = ops.map(\.attemptCount).max() ?? 1
        guard maxAttempt < maxAttempts else {
            // Park the batch: leave the ops in place at the attempt cap and stop retrying now.
            // They're picked up again on the next lifecycle flush / explicit drain, never
            // hot-looped. Settings can surface these for manual retry (Task 7).
            return
        }

        let backoff = min(pow(2.0, Double(maxAttempt)), maxBackoffSeconds)
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(backoff))
            guard !Task.isCancelled else { return }
            await self.drain()
        }
    }

    // MARK: - Coalescing

    private struct EntityKey: Hashable {
        let type: PendingSyncOp.EntityType
        let id: UUID
    }

    /// Collapses multiple ops per entity to the most recent one (last-writer-wins), so a burst
    /// of edits — or an edit then a delete — becomes a single push action.
    private func coalesce(_ ops: [PendingSyncOp]) -> [EntityKey: PendingSyncOp] {
        var latest: [EntityKey: PendingSyncOp] = [:]
        for op in ops.sorted(by: { $0.enqueuedAt < $1.enqueuedAt }) {
            guard let type = op.entityTypeValue else { continue }
            latest[EntityKey(type: type, id: op.entityID)] = op
        }
        return latest
    }

    // MARK: - Fetch helpers

    private func fetchPendingOps() -> [PendingSyncOp] {
        let descriptor = FetchDescriptor<PendingSyncOp>(
            sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchLearning(id: UUID) -> Learning? {
        var descriptor = FetchDescriptor<Learning>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchReflection(id: UUID) -> Reflection? {
        var descriptor = FetchDescriptor<Reflection>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchAllLearnings() -> [Learning] {
        (try? modelContext.fetch(FetchDescriptor<Learning>())) ?? []
    }

    private func fetchAllReflections() -> [Reflection] {
        (try? modelContext.fetch(FetchDescriptor<Reflection>())) ?? []
    }

    private func refreshPendingCount() {
        pendingCount = (try? modelContext.fetchCount(FetchDescriptor<PendingSyncOp>())) ?? 0
    }
}

// MARK: - Errors

enum SyncCoordinatorError: Error, LocalizedError {
    case cloudUnavailable
    case reconcileFailed(String)

    var errorDescription: String? {
        switch self {
        case .cloudUnavailable:
            return "iCloud is not available"
        case .reconcileFailed(let message):
            return message
        }
    }
}
