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

    /// Grace period protecting freshly written cache rows from delete-stale during the
    /// CloudKit accept→shared-DB-mirror lag (a just-accepted zone isn't returned by
    /// `sharedDB.allRecordZones()` for a short while after `acceptShare`).
    private static let reconcileGraceInterval: TimeInterval = 30

    /// Upserts every fetched space by unique `id` and deletes cache rows no longer present
    /// in the (complete, both-lane) fetch. Only reached once both cloud fetches succeed.
    private func reconcileCache(with spaces: [Space]) throws {
        for space in spaces {
            try upsert(space)
        }

        // Prune rows the fetch no longer returned — but keep very recently written rows
        // (e.g. a just-accepted space whose shared-DB zone CloudKit hasn't mirrored yet),
        // so a reconcile racing the accept→mirror lag can't evict it.
        let fetchedIDs = Set(spaces.map { $0.id })
        let staleCutoff = Date().addingTimeInterval(-Self.reconcileGraceInterval)
        let existing = try modelContext.fetch(FetchDescriptor<CachedSpace>())
        for row in existing where !fetchedIDs.contains(row.id) && row.lastFetchedAt < staleCutoff {
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

    // MARK: - Reflections

    func cachedReflections(spaceID: String) -> [SpaceReflection] {
        let target = spaceID
        let descriptor = FetchDescriptor<CachedSpaceReflection>(
            predicate: #Predicate { $0.spaceID == target },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    func fetchReflections(for space: Space) async throws -> [SpaceReflection] {
        let fetched = try await cloudService.fetchReflections(in: space.zoneID)
        try reconcileReflections(fetched, spaceID: space.id)
        return cachedReflections(spaceID: space.id)
    }

    func createReflection(in space: Space, title: String, promptText: String) async throws -> SpaceReflection {
        let reflection = try await cloudService.createReflection(
            in: space.zoneID,
            spaceID: space.id,
            title: title,
            promptText: promptText
        )
        try upsertReflection(reflection)
        try modelContext.save()
        return reflection
    }

    // MARK: - Responses

    func cachedResponses(reflectionID: String) -> [SpaceResponse] {
        let target = reflectionID
        let descriptor = FetchDescriptor<CachedSpaceResponse>(
            predicate: #Predicate { $0.reflectionID == target },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    func fetchResponses(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceResponse] {
        let fetched = try await cloudService.fetchResponses(for: reflection, in: space.zoneID)
        try reconcileResponses(fetched, reflectionID: reflection.id)
        return cachedResponses(reflectionID: reflection.id)
    }

    func createResponse(to reflection: SpaceReflection, in space: Space, body: String) async throws -> SpaceResponse {
        let response = try await cloudService.createResponse(to: reflection, body: body, in: space.zoneID)
        try upsertResponse(response)
        try modelContext.save()
        return response
    }

    // MARK: - Delete own content

    func deleteContent(id: String, in space: Space) async throws {
        try await cloudService.deleteRecord(id: id, in: space.zoneID)
        try removeCachedContent(id: id)
    }

    // MARK: - Child cache reconciliation

    private func reconcileReflections(_ reflections: [SpaceReflection], spaceID: String) throws {
        for reflection in reflections {
            try upsertReflection(reflection)
        }

        let fetchedIDs = Set(reflections.map { $0.id })
        let staleCutoff = Date().addingTimeInterval(-Self.reconcileGraceInterval)
        let target = spaceID
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.spaceID == target })
        )
        for row in existing where !fetchedIDs.contains(row.id) && row.lastFetchedAt < staleCutoff {
            try removeCachedResponses(reflectionID: row.id)
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    private func reconcileResponses(_ responses: [SpaceResponse], reflectionID: String) throws {
        for response in responses {
            try upsertResponse(response)
        }

        let fetchedIDs = Set(responses.map { $0.id })
        let staleCutoff = Date().addingTimeInterval(-Self.reconcileGraceInterval)
        let target = reflectionID
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedSpaceResponse>(predicate: #Predicate { $0.reflectionID == target })
        )
        for row in existing where !fetchedIDs.contains(row.id) && row.lastFetchedAt < staleCutoff {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    private func upsertReflection(_ reflection: SpaceReflection) throws {
        let id = reflection.id
        let descriptor = FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.spaceID = reflection.spaceID
            existing.title = reflection.title
            existing.promptText = reflection.promptText
            existing.authorRecordName = reflection.authorRecordName
            existing.authorDisplayName = reflection.authorDisplayName
            existing.createdAt = reflection.createdAt
            existing.modifiedAt = reflection.modifiedAt
            existing.isMine = reflection.isMine
            existing.lastFetchedAt = Date()
        } else {
            modelContext.insert(CachedSpaceReflection(from: reflection))
        }
    }

    private func upsertResponse(_ response: SpaceResponse) throws {
        let id = response.id
        let descriptor = FetchDescriptor<CachedSpaceResponse>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.reflectionID = response.reflectionID
            existing.body = response.body
            existing.authorRecordName = response.authorRecordName
            existing.authorDisplayName = response.authorDisplayName
            existing.createdAt = response.createdAt
            existing.isMine = response.isMine
            existing.lastFetchedAt = Date()
        } else {
            modelContext.insert(CachedSpaceResponse(from: response))
        }
    }

    /// Removes a reflection (and its responses) or a response by id. CloudKit cascades on
    /// the server via `parent`; the local cache must not orphan the children.
    private func removeCachedContent(id: String) throws {
        let reflectionID = id
        let reflectionDescriptor = FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.id == reflectionID })
        if let reflection = try modelContext.fetch(reflectionDescriptor).first {
            try removeCachedResponses(reflectionID: reflection.id)
            modelContext.delete(reflection)
        }

        let responseID = id
        let responseDescriptor = FetchDescriptor<CachedSpaceResponse>(predicate: #Predicate { $0.id == responseID })
        if let response = try modelContext.fetch(responseDescriptor).first {
            modelContext.delete(response)
        }

        try modelContext.save()
    }

    /// Deletes all cached responses under a reflection. Does not save — callers batch saves.
    private func removeCachedResponses(reflectionID: String) throws {
        let target = reflectionID
        let descriptor = FetchDescriptor<CachedSpaceResponse>(predicate: #Predicate { $0.reflectionID == target })
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
    }
}
