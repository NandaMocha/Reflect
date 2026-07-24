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

    /// When true, mutations do not enqueue and drains are skipped. Brackets restore / bulk
    /// import so seeding the local store doesn't queue a re-upload storm (Task 6).
    var paused: Bool = false

    /// Master switch (Settings toggle, Task 7). Defaults off until the feature fully lands;
    /// `UserDefaults.bool` returns false for an absent key, which is the intended default.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
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

    // MARK: - Initialization

    init(cloudSyncService: CloudSyncServiceProtocol, modelContext: ModelContext) {
        self.cloudSyncService = cloudSyncService
        self.modelContext = modelContext
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
        guard isEnabled, !paused else { return }
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
        guard isEnabled, !paused else { return }

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
            }
        } catch {
            handleDrainFailure(ops: ops, error: error)
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

    private func refreshPendingCount() {
        pendingCount = (try? modelContext.fetchCount(FetchDescriptor<PendingSyncOp>())) ?? 0
    }
}
