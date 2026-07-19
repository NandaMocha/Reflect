import CloudKit
import Foundation
import SwiftData

/// Cloud-through-cache implementation of `SpaceRepositoryProtocol`.
///
/// Reads paint from the `SpaceStore` cache and reconcile against CloudKit; writes go to
/// the cloud service first and only upsert the cache on success. `@MainActor` because the
/// injected context is `SpaceStore.container.mainContext` (see DIContainer, T11).
@MainActor
final class SpaceRepository: SpaceRepositoryProtocol {

    // MARK: - Dependencies

    private let cloudService: SpaceCloudServiceProtocol
    private let modelContext: ModelContext

    // MARK: - Initialization

    init(cloudService: SpaceCloudServiceProtocol, modelContext: ModelContext) {
        self.cloudService = cloudService
        self.modelContext = modelContext
    }

    // MARK: - Read

    func cachedSpaces() -> [Space] {
        let descriptor = FetchDescriptor<CachedSpace>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    func fetchSpaces(forceRefresh: Bool) async throws -> [Space] {
        let cached = cachedSpaces()
        if !forceRefresh && !cached.isEmpty {
            return cached
        }

        // Both lanes are fetched before we touch the cache: if either throws we bail out
        // without reconciling, so a transient partial fetch can never wipe the cache.
        let owned = try await cloudService.fetchOwnedSpaces()
        let joined = try await cloudService.fetchJoinedSpaces()

        try reconcileCache(with: owned + joined)
        return cachedSpaces()
    }

    // MARK: - Write (cloud leads, cache follows)

    func createSpace(name: String, detail: String?, emoji: String?) async throws -> Space {
        let (space, _) = try await cloudService.createSpace(name: name, detail: detail, emoji: emoji)
        try upsert(space)
        try modelContext.save()
        return space
    }

    func shareForSpace(_ space: Space) async throws -> CKShare {
        try await cloudService.fetchShare(for: space.zoneID)
    }

    func acceptInvite(metadata: CKShare.Metadata) async throws -> Space {
        let space = try await cloudService.acceptShare(metadata: metadata)
        try upsert(space)
        try modelContext.save()
        return space
    }

    func deleteSpace(_ space: Space) async throws {
        try await cloudService.deleteSpace(space.zoneID)
        try removeCached(id: space.id)
    }

    func leaveSpace(_ space: Space) async throws {
        try await cloudService.leaveSpace(space.zoneID)
        try removeCached(id: space.id)
    }

    // MARK: - Cache reconciliation

    /// Upserts every fetched space by unique `id` and deletes cache rows no longer present
    /// in the (complete, both-lane) fetch. Only reached once both cloud fetches succeed.
    private func reconcileCache(with spaces: [Space]) throws {
        for space in spaces {
            try upsert(space)
        }

        let fetchedIDs = Set(spaces.map { $0.id })
        let existing = try modelContext.fetch(FetchDescriptor<CachedSpace>())
        for row in existing where !fetchedIDs.contains(row.id) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    /// Insert-or-update a single row by unique `id`. Does not save — callers batch saves.
    private func upsert(_ space: Space) throws {
        let id = space.id
        let descriptor = FetchDescriptor<CachedSpace>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = space.name
            existing.detail = space.detail
            existing.emoji = space.emoji
            existing.isOwner = space.isOwner
            existing.zoneName = space.zoneID.zoneName
            existing.ownerName = space.zoneID.ownerName
            existing.laneRawValue = space.zoneID.lane == .privateDB ? "privateDB" : "sharedDB"
            existing.createdAt = space.createdAt
            existing.participantCount = space.participantCount
            existing.lastFetchedAt = Date()
        } else {
            modelContext.insert(CachedSpace(from: space))
        }
    }

    private func removeCached(id: String) throws {
        let descriptor = FetchDescriptor<CachedSpace>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }
}
