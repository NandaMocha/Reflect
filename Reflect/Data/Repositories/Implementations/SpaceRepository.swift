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

    func createSpace(name: String, detail: String?, iconName: String?, colorHex: String?) async throws -> (Space, CKShare) {
        let (space, share) = try await cloudService.createSpace(name: name, detail: detail, iconName: iconName, colorHex: colorHex)
        try upsert(space)
        try modelContext.save()
        // Hand back the share the cloud service already created; re-fetching it here (or in the
        // caller) races CloudKit's read-after-write on the just-written zone and can spuriously
        // throw `.notFound`.
        return (space, share)
    }

    func shareForSpace(_ space: Space) async throws -> CKShare {
        try await cloudService.fetchShare(for: space.zoneID)
    }

    func members(of space: Space) async throws -> [SpaceMember] {
        try await cloudService.fetchMembers(for: space.zoneID)
    }

    func registerDisplayName(_ displayName: String, in space: Space) async throws {
        try await cloudService.registerDisplayName(displayName, in: space.zoneID, spaceID: space.id)
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
            try removeCachedChildren(spaceID: row.id)
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
            existing.iconName = space.iconName
            existing.colorHex = space.colorHex
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
            try removeCachedChildren(spaceID: id)
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    /// Deletes all cached reflections (and their responses) for a space — the flattened
    /// cache has no cascade, so a space delete/leave/prune must clean up children itself.
    /// Does not save — callers batch saves.
    private func removeCachedChildren(spaceID: String) throws {
        let target = spaceID
        let reflections = try modelContext.fetch(
            FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.spaceID == target })
        )
        for reflection in reflections {
            try removeCachedResponses(reflectionID: reflection.id)
            try removeCachedAnswers(reflectionID: reflection.id)
            modelContext.delete(reflection)
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
        let delta = try await cloudService.fetchChanges(in: space.zoneID, spaceID: space.id)
        try applyZoneDelta(delta, spaceID: space.id)
        return cachedReflections(spaceID: space.id)
    }

    func createReflection(in space: Space, title: String, note: String?, questions: [SpaceQuestion], imageData: Data?) async throws -> SpaceReflection {
        let reflection = try await cloudService.createReflection(
            in: space.zoneID,
            spaceID: space.id,
            title: title,
            note: note,
            questions: questions,
            imageData: imageData
        )
        try upsertReflection(reflection)
        try modelContext.save()
        return reflection
    }

    /// Updates a reflection's title/note/questions. Questions removed relative to
    /// `reflection.questions` cascade-delete every participant's answer to them (clarified
    /// decision 6: hard-delete, not orphan, not blocked) before the reflection is saved.
    /// Ordering: cascade deletes (cloud + cache) -> reflection save (cloud) -> cache upsert.
    func updateReflectionQuestions(_ reflection: SpaceReflection, in space: Space, title: String, note: String?, questions: [SpaceQuestion]) async throws -> SpaceReflection {
        let oldQuestionIDs = Set(reflection.questions.map { $0.id })
        let newQuestionIDs = Set(questions.map { $0.id })
        let removedQuestionIDs = oldQuestionIDs.subtracting(newQuestionIDs)

        if !removedQuestionIDs.isEmpty {
            // Fetch once up front so every removed question's answers (from any
            // participant) are known by id — deletes below go straight by id rather than
            // re-discovering each answer's record.
            let answers = try await fetchAnswers(for: reflection, in: space)
            for answer in answers where removedQuestionIDs.contains(answer.questionId) {
                try await cloudService.deleteRecord(id: answer.id, in: space.zoneID)
                try removeCachedContent(id: answer.id)
            }
        }

        let updated = try await cloudService.updateReflection(id: reflection.id, in: space.zoneID, title: title, note: note, questions: questions)
        try upsertReflection(updated)
        try modelContext.save()
        return updated
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
        let delta = try await cloudService.fetchChanges(in: space.zoneID, spaceID: space.id)
        try applyZoneDelta(delta, spaceID: space.id)
        return cachedResponses(reflectionID: reflection.id)
    }

    // MARK: - Delete own content

    func deleteContent(id: String, in space: Space) async throws {
        try await cloudService.deleteRecord(id: id, in: space.zoneID)
        try removeCachedContent(id: id)
    }

    // MARK: - Answers

    func cachedAnswers(reflectionID: String) -> [SpaceAnswer] {
        let target = reflectionID
        let descriptor = FetchDescriptor<CachedAnswer>(
            predicate: #Predicate { $0.reflectionID == target },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    func fetchAnswers(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceAnswer] {
        let delta = try await cloudService.fetchChanges(in: space.zoneID, spaceID: space.id)
        try applyZoneDelta(delta, spaceID: space.id)
        return cachedAnswers(reflectionID: reflection.id)
    }

    func upsertAnswer(to reflection: SpaceReflection, questionId: String, text: String, imageData: Data?, in space: Space) async throws -> SpaceAnswer {
        let answer = try await cloudService.upsertAnswer(to: reflection, questionId: questionId, text: text, imageData: imageData, in: space.zoneID)
        try upsertAnswer(answer)
        try modelContext.save()
        return answer
    }

    func deleteOwnAnswer(_ answer: SpaceAnswer, in space: Space) async throws {
        try await cloudService.deleteRecord(id: answer.id, in: space.zoneID)
        try removeCachedContent(id: answer.id)
    }

    // MARK: - Child cache reconciliation (T27)

    /// Applies one zone delta to the cache. On incremental deltas, absence means
    /// *unchanged* — rows are only removed on an explicit deletion from CloudKit. Only a
    /// full snapshot (nil/expired token) may run the set-difference prune, with the same
    /// grace window as the old reconcile.
    private func applyZoneDelta(_ delta: SpaceZoneDelta, spaceID: String) throws {
        for reflection in delta.reflections {
            try upsertReflection(reflection)
        }
        for answer in delta.answers {
            try upsertAnswer(answer)
        }
        for deletedID in delta.deletedRecordIDs {
            try removeCachedContentRow(id: deletedID)
        }

        try refreshAuthorNames(delta.authorNames, spaceID: spaceID)

        if delta.isFullSnapshot {
            try pruneRowsAbsent(from: delta, spaceID: spaceID)
        }
        try modelContext.save()
    }

    /// Set-difference prune for full snapshots only: anything cached under this space that
    /// the complete zone fetch didn't return (and that isn't inside the write-grace window)
    /// no longer exists upstream.
    private func pruneRowsAbsent(from delta: SpaceZoneDelta, spaceID: String) throws {
        let staleCutoff = Date().addingTimeInterval(-Self.reconcileGraceInterval)
        let target = spaceID

        let fetchedReflectionIDs = Set(delta.reflections.map { $0.id })
        let reflectionRows = try modelContext.fetch(
            FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.spaceID == target })
        )
        var keptReflectionIDs: Set<String> = []
        for row in reflectionRows {
            if !fetchedReflectionIDs.contains(row.id) && row.lastFetchedAt < staleCutoff {
                try removeCachedResponses(reflectionID: row.id)
                try removeCachedAnswers(reflectionID: row.id)
                modelContext.delete(row)
            } else {
                keptReflectionIDs.insert(row.id)
            }
        }

        // Same set-difference prune for answers, scoped the same way responses used to be.
        let fetchedAnswerIDs = Set(delta.answers.map { $0.id })
        let answerRows = try modelContext.fetch(FetchDescriptor<CachedAnswer>())
        for row in answerRows
        where keptReflectionIDs.contains(row.reflectionID)
            && !fetchedAnswerIDs.contains(row.id)
            && row.lastFetchedAt < staleCutoff {
            modelContext.delete(row)
        }
    }

    /// Pushes the latest author-name resolution onto cached rows, so a member's profile
    /// rename propagates to rows whose records didn't change in this delta. Never clears
    /// a name — an unresolved author keeps whatever was cached.
    private func refreshAuthorNames(_ names: [String: String], spaceID: String) throws {
        guard !names.isEmpty else { return }
        let target = spaceID
        let reflectionRows = try modelContext.fetch(
            FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.spaceID == target })
        )
        let reflectionIDs = Set(reflectionRows.map { $0.id })
        for row in reflectionRows where !row.isMine {
            if let author = row.authorRecordName, let name = names[author], row.authorDisplayName != name {
                row.authorDisplayName = name
            }
        }
        let responseRows = try modelContext.fetch(FetchDescriptor<CachedSpaceResponse>())
        for row in responseRows where !row.isMine && reflectionIDs.contains(row.reflectionID) {
            if let author = row.authorRecordName, let name = names[author], row.authorDisplayName != name {
                row.authorDisplayName = name
            }
        }
        let answerRows = try modelContext.fetch(FetchDescriptor<CachedAnswer>())
        for row in answerRows where !row.isMine && reflectionIDs.contains(row.reflectionID) {
            if let author = row.authorRecordName, let name = names[author], row.authorDisplayName != name {
                row.authorDisplayName = name
            }
        }
    }

    private func upsertReflection(_ reflection: SpaceReflection) throws {
        let id = reflection.id
        let descriptor = FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.spaceID = reflection.spaceID
            existing.title = reflection.title
            existing.note = reflection.note
            existing.questionsData = (try? JSONEncoder().encode(reflection.questions)) ?? Data()
            // T28: an unchanged record whose asset failed to stage locally must not wipe
            // the cached photo — only take the incoming value when there is one, or when
            // the record genuinely changed upstream.
            if reflection.imageData != nil || existing.modifiedAt != reflection.modifiedAt {
                existing.imageData = reflection.imageData
            }
            existing.authorRecordName = reflection.authorRecordName
            if let name = reflection.authorDisplayName {
                existing.authorDisplayName = name
            }
            existing.createdAt = reflection.createdAt
            existing.modifiedAt = reflection.modifiedAt
            // Sticky true: `isMine` is fail-closed to false in SpaceCloudService.isMine(_:lane:myUserRecordName:)
            // whenever the current user's record name hasn't resolved yet (e.g. a
            // transient CKContainer.userRecordID() lookup on this pass), so a genuinely
            // self-authored row can be recomputed as false on a later resync. Never let a
            // resync downgrade a row already known to be mine — only let it flip false → true.
            existing.isMine = existing.isMine || reflection.isMine
            existing.lastFetchedAt = Date()
        } else {
            modelContext.insert(CachedSpaceReflection(from: reflection))
        }
    }

    private func upsertAnswer(_ answer: SpaceAnswer) throws {
        let id = answer.id
        let descriptor = FetchDescriptor<CachedAnswer>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.reflectionID = answer.reflectionID
            existing.questionId = answer.questionId
            existing.text = answer.text
            if answer.imageData != nil || existing.modifiedAt != answer.modifiedAt {
                existing.imageData = answer.imageData
            }
            existing.authorRecordName = answer.authorRecordName
            if let name = answer.authorDisplayName {
                existing.authorDisplayName = name
            }
            existing.createdAt = answer.createdAt
            existing.modifiedAt = answer.modifiedAt
            // Sticky true: see the matching comment in upsertReflection — never let a
            // resync downgrade a row already known to be mine, only let it flip false → true.
            existing.isMine = existing.isMine || answer.isMine
            existing.lastFetchedAt = Date()
        } else {
            modelContext.insert(CachedAnswer(from: answer))
        }
    }

    /// Removes a reflection (and its responses and answers) or a response/answer by id from
    /// the cache. The cloud service cascades the delete to child response/answer records on
    /// the server (parent references with action `.none` do NOT auto-cascade), so the cache
    /// mirrors that here.
    private func removeCachedContent(id: String) throws {
        try removeCachedContentRow(id: id)
        try modelContext.save()
    }

    /// Non-saving variant used by `applyZoneDelta` (which batches one save per delta).
    private func removeCachedContentRow(id: String) throws {
        let reflectionID = id
        let reflectionDescriptor = FetchDescriptor<CachedSpaceReflection>(predicate: #Predicate { $0.id == reflectionID })
        if let reflection = try modelContext.fetch(reflectionDescriptor).first {
            try removeCachedResponses(reflectionID: reflection.id)
            try removeCachedAnswers(reflectionID: reflection.id)
            modelContext.delete(reflection)
        }

        let responseID = id
        let responseDescriptor = FetchDescriptor<CachedSpaceResponse>(predicate: #Predicate { $0.id == responseID })
        if let response = try modelContext.fetch(responseDescriptor).first {
            modelContext.delete(response)
        }

        let answerID = id
        let answerDescriptor = FetchDescriptor<CachedAnswer>(predicate: #Predicate { $0.id == answerID })
        if let answer = try modelContext.fetch(answerDescriptor).first {
            modelContext.delete(answer)
        }
    }

    /// Deletes all cached responses under a reflection. Does not save — callers batch saves.
    private func removeCachedResponses(reflectionID: String) throws {
        let target = reflectionID
        let descriptor = FetchDescriptor<CachedSpaceResponse>(predicate: #Predicate { $0.reflectionID == target })
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
    }

    /// Deletes all cached answers under a reflection. Does not save — callers batch saves.
    private func removeCachedAnswers(reflectionID: String) throws {
        let target = reflectionID
        let descriptor = FetchDescriptor<CachedAnswer>(predicate: #Predicate { $0.reflectionID == target })
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
    }
}
