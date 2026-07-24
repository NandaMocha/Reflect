import Foundation
import SwiftData

/// Transactional-outbox record for incremental iCloud auto-sync.
///
/// One row is enqueued in the SAME `ModelContext.save()` as the entity mutation
/// that produced it, so an entity change and its sync intent commit atomically.
/// `SyncCoordinator` later drains these, pushes them to the private CloudKit
/// database, and deletes the drained rows on success.
///
/// Intentionally has **no** SwiftData relationship to `Learning`/`Reflection`: a
/// delete op must outlive the row it refers to. The entity is addressed by
/// `entityID` (which equals the CloudKit `localID` / deterministic recordName).
@preconcurrency @Model
final class PendingSyncOp {
    @Attribute(.unique) var id: UUID

    /// `learning` | `reflection` — see `EntityType`.
    var entityType: String

    /// The mutated entity's `localID`. Doubles as the deterministic CloudKit
    /// recordName so upserts are idempotent and deletes need no prior lookup.
    var entityID: UUID

    /// `upsert` | `delete` — see `Operation`.
    var op: String

    var enqueuedAt: Date = Date()
    var attemptCount: Int = 0
    var lastError: String? = nil

    init(
        entityType: EntityType,
        entityID: UUID,
        op: Operation,
        enqueuedAt: Date = Date()
    ) {
        self.id = UUID()
        self.entityType = entityType.rawValue
        self.entityID = entityID
        self.op = op.rawValue
        self.enqueuedAt = enqueuedAt
    }

    // MARK: - Typed accessors

    /// String columns (not enum-typed) so SwiftData migrations stay trivial and
    /// an unknown future value never crashes a decode; callers use these helpers.
    enum EntityType: String {
        case learning
        case reflection
    }

    enum Operation: String {
        case upsert
        case delete
    }

    var entityTypeValue: EntityType? { EntityType(rawValue: entityType) }
    var operationValue: Operation? { Operation(rawValue: op) }
}
