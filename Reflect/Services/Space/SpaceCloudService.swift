import CloudKit
import Foundation

/// Concrete CloudKit implementation of the Space sharing core.
///
/// Every operation is routed by `SpaceZoneRef.lane`: `.privateDB` for zones the current
/// user owns, `.sharedDB` for zones mirrored in after accepting an invite. This mirrors
/// the "two databases, one abstraction" design in docs/features/space-plan.md §3.
///
/// NOTE on sync strategy: this implements the **manual-operations path** (explicit
/// `CKModifyRecordsOperation` / async `CKDatabase` convenience methods, wrapped in
/// retry-with-backoff). `CKSyncEngine` is evaluated later (T22) for the background
/// sync/subscription loop only — creation, sharing, and accept are explicit CloudKit
/// operations either way (CKSyncEngine doesn't replace them), so none of this is
/// throwaway if T22 adopts it.
final class SpaceCloudService: SpaceCloudServiceProtocol {

    // MARK: - Dependencies

    /// Explicit container identifier — deliberately not the framework's zero-config
    /// default initializer. Matches the entitlement in Reflect.entitlements
    /// (`com.apple.developer.icloud-container-identifiers`).
    private let container = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")

    private lazy var privateDB: CKDatabase = container.privateCloudDatabase
    private lazy var sharedDB: CKDatabase = container.sharedCloudDatabase

    /// The current user's record name in this container, resolved once and reused for
    /// `isMine` comparisons. Guarded by `userRecordNameLock` because the service is not
    /// actor-isolated and fetches can run concurrently.
    private var cachedUserRecordName: String?
    private let userRecordNameLock = NSLock()

    // MARK: - Availability

    func checkAvailability() async -> CloudAvailability {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .temporarilyUnavailable
            }
        } catch {
            return .networkUnavailable
        }
    }

    // MARK: - Create

    func createSpace(name: String, detail: String?, emoji: String?) async throws -> (Space, CKShare) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw SpaceError.nameRequired }
        guard trimmedName.count <= 50 else { throw SpaceError.nameTooLong }

        let availability = await checkAvailability()
        guard availability.isAvailable else { throw SpaceError.iCloudUnavailable }

        // 1. Custom zone, one per space, always in the PRIVATE database (only the
        //    owner's private DB can host a zone that gets shared out).
        let zone = CKRecordZone(zoneName: "Space-\(UUID().uuidString)")
        _ = try await withRetry { try await self.privateDB.save(zone) }

        // 2. Root record + CKShare, built but not yet saved.
        let spaceRecord = SpaceRecordMapper.makeSpaceRecord(
            zoneID: zone.zoneID,
            name: trimmedName,
            detail: detail,
            emoji: emoji
        )
        let share = CKShare(rootRecord: spaceRecord)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = trimmedName as CKRecordValue

        // 3. Root + share saved atomically — see `saveRootAndShare` below.
        let (savedSpaceRecord, savedShare) = try await saveRootAndShare(spaceRecord, share, in: privateDB)

        guard let space = SpaceRecordMapper.space(
            from: savedSpaceRecord,
            lane: .privateDB,
            isOwner: true,
            participantCount: savedShare.participants.count
        ) else {
            throw SpaceError.shareFailed("Could not map the newly saved Space record")
        }

        return (space, savedShare)
    }

    /// Saves the root `Space` record and its `CKShare` in a single
    /// `CKModifyRecordsOperation`. CloudKit requires this: a `CKShare` saved without its
    /// root record present in the same operation (or vice versa) is rejected server-side.
    private func saveRootAndShare(
        _ spaceRecord: CKRecord,
        _ share: CKShare,
        in database: CKDatabase
    ) async throws -> (CKRecord, CKShare) {
        try await withRetry {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(CKRecord, CKShare), Error>) in
                let operation = CKModifyRecordsOperation(recordsToSave: [spaceRecord, share], recordIDsToDelete: nil)
                operation.savePolicy = .allKeys
                operation.isAtomic = true
                operation.qualityOfService = .userInitiated
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        // CKModifyRecordsOperation updates the CKRecord/CKShare instances
                        // it was given in place with server-assigned metadata, so the
                        // objects we passed in are already the saved ones.
                        continuation.resume(returning: (spaceRecord, share))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        }
    }

    // MARK: - Fetch owned / joined

    func fetchOwnedSpaces() async throws -> [Space] {
        try await fetchSpaces(in: privateDB, lane: .privateDB, isOwner: true)
    }

    func fetchJoinedSpaces() async throws -> [Space] {
        // Shared-DB zone IDs already carry the OWNER's name (returned by CloudKit, not
        // constructed locally) — never build a shared-DB zoneID with
        // CKCurrentUserDefaultName. We just read zone.zoneID.ownerName off the objects
        // CloudKit gives us in `fetchSpaces`.
        try await fetchSpaces(in: sharedDB, lane: .sharedDB, isOwner: false)
    }

    private func fetchSpaces(in database: CKDatabase, lane: SpaceLane, isOwner: Bool) async throws -> [Space] {
        let availability = await checkAvailability()
        guard availability.isAvailable else { throw SpaceError.iCloudUnavailable }

        let zones = try await withRetry { try await database.allRecordZones() }
        let defaultZoneName = CKRecordZone.default().zoneID.zoneName

        var spaces: [Space] = []
        for zone in zones where zone.zoneID.zoneName != defaultZoneName {
            guard let rootRecord = try await fetchRootSpaceRecord(in: zone.zoneID, database: database) else {
                continue
            }
            let count = await participantCount(for: rootRecord, in: database)
            if let space = SpaceRecordMapper.space(from: rootRecord, lane: lane, isOwner: isOwner, participantCount: count) {
                spaces.append(space)
            }
        }
        return spaces
    }

    /// Finds a zone's single root `Space` record.
    ///
    /// Uses a zone-changes fetch rather than a `CKQuery`: querying (even with a
    /// `TRUEPREDICATE`) requires the record type's `recordName` system field to be marked
    /// **Queryable**, and auto-created Development schema leaves that index off — a
    /// `CKQuery` there fails with "Field 'recordName' is not marked queryable".
    /// `CKFetchRecordZoneChangesOperation` reads every record in the zone with no index
    /// requirement, and it's the same primitive T22's sync loop will build on.
    private func fetchRootSpaceRecord(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> CKRecord? {
        let records = try await fetchAllRecords(in: zoneID, database: database)
        return records.first { $0.recordType == SpaceRecordType.space }
    }

    /// Fetches every record currently in a custom zone via a one-shot zone-changes
    /// operation (nil change token → full zone contents). Index-free; see
    /// `fetchRootSpaceRecord` for why we avoid `CKQuery`.
    private func fetchAllRecords(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        try await withRetry {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
                let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                let operation = CKFetchRecordZoneChangesOperation(
                    recordZoneIDs: [zoneID],
                    configurationsByRecordZoneID: [zoneID: config]
                )
                operation.fetchAllChanges = true
                operation.qualityOfService = .userInitiated

                var records: [CKRecord] = []
                operation.recordWasChangedBlock = { _, result in
                    if case .success(let record) = result {
                        records.append(record)
                    }
                }
                operation.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: records)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        }
    }

    /// Best-effort participant count via the root record's `share` reference. Falls
    /// back to 1 (owner only) rather than failing the whole space list on a transient
    /// share-fetch error — participant count is informational, not load-bearing.
    private func participantCount(for record: CKRecord, in database: CKDatabase) async -> Int {
        guard let shareReference = record.share else { return 1 }
        guard let shareRecord = try? await database.record(for: shareReference.recordID),
              let share = shareRecord as? CKShare else {
            return 1
        }
        return share.participants.count
    }

    // MARK: - Fetch share

    func fetchShare(for zone: SpaceZoneRef) async throws -> CKShare {
        let database = database(for: zone.lane)
        let zoneID = CKRecordZone.ID(zoneName: zone.zoneName, ownerName: zone.ownerName)

        guard let rootRecord = try await fetchRootSpaceRecord(in: zoneID, database: database) else {
            throw SpaceError.notFound
        }
        guard let shareReference = rootRecord.share else {
            throw SpaceError.shareFailed("Space has no associated share")
        }

        let shareRecord = try await withRetry { try await database.record(for: shareReference.recordID) }
        guard let share = shareRecord as? CKShare else {
            throw SpaceError.shareFailed("Fetched record was not a CKShare")
        }
        return share
    }

    // MARK: - Accept

    func acceptShare(metadata: CKShare.Metadata) async throws -> Space {
        do {
            try await withRetry {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
                    operation.qualityOfService = .userInitiated
                    operation.acceptSharesResultBlock = { result in
                        switch result {
                        case .success:
                            continuation.resume(returning: ())
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    self.container.add(operation)
                }
            }
        } catch {
            throw Self.acceptError(from: error)
        }

        // After acceptance the zone is mirrored into the SHARED database; fetch the
        // root record from there (not the private DB — we're not the owner).
        // `hierarchicalRootRecordID` is the non-deprecated iOS 17+ replacement for the
        // old `rootRecordID`; our share has no nested hierarchy so both point to the
        // same `Space` root record.
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw SpaceError.acceptFailed("Share metadata has no root record ID")
        }
        let rootRecord: CKRecord
        do {
            rootRecord = try await withRetry { try await self.sharedDB.record(for: rootRecordID) }
        } catch {
            throw Self.acceptError(from: error)
        }
        let participantCount = metadata.share.participants.count

        guard let space = SpaceRecordMapper.space(
            from: rootRecord,
            lane: .sharedDB,
            isOwner: false,
            participantCount: participantCount
        ) else {
            throw SpaceError.acceptFailed("Could not map the accepted Space record")
        }
        return space
    }

    /// Turns a raw `CKError` from the accept path into something a user can act on.
    ///
    /// The raw `localizedDescription` for these ("Record not found", "Invalid arguments")
    /// tells the user nothing. The most common real cause in the field is an environment
    /// mismatch — a share created by a Development-signed build can't be accepted by a
    /// TestFlight/App Store build, because CloudKit's Development and Production
    /// environments are entirely separate stores. That surfaces as `unknownItem` /
    /// `zoneNotFound`, so the copy points at re-sending the invite from matching builds.
    private static func acceptError(from error: Error) -> SpaceError {
        guard let ckError = error as? CKError else {
            return .acceptFailed(error.localizedDescription)
        }
        switch ckError.code {
        case .unknownItem, .zoneNotFound, .invalidArguments:
            return .acceptFailed(
                "this invite is no longer valid, or it came from a different version of Reflect. Ask the owner to send a new one."
            )
        case .participantMayNeedVerification:
            return .acceptFailed(
                "sign in to iCloud with the account the invite was sent to."
            )
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .iCloudUnavailable
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return .acceptFailed("iCloud is unreachable right now. Try again in a moment.")
        default:
            return .acceptFailed(ckError.localizedDescription)
        }
    }

    // MARK: - Delete (owner) / Leave (participant)

    func deleteSpace(_ zone: SpaceZoneRef) async throws {
        assert(zone.lane == .privateDB, "deleteSpace must only be called for owned (private DB) spaces")
        guard zone.lane == .privateDB else { throw SpaceError.notOwner }

        let zoneID = CKRecordZone.ID(zoneName: zone.zoneName, ownerName: zone.ownerName)
        _ = try await withRetry { try await self.privateDB.deleteRecordZone(withID: zoneID) }
    }

    func leaveSpace(_ zone: SpaceZoneRef) async throws {
        assert(zone.lane == .sharedDB, "leaveSpace must only be called for joined (shared DB) spaces")
        guard zone.lane == .sharedDB else {
            throw SpaceError.syncFailed("leaveSpace requires a shared-DB zone reference")
        }

        // Deleting the mirrored zone from MY shared DB removes only my access — it does
        // not touch the owner's private-DB zone or other participants' access.
        let zoneID = CKRecordZone.ID(zoneName: zone.zoneName, ownerName: zone.ownerName)
        _ = try await withRetry { try await self.sharedDB.deleteRecordZone(withID: zoneID) }
    }

    // MARK: - Child records (SpaceReflection / Response)

    func fetchReflections(in zone: SpaceZoneRef) async throws -> [SpaceReflection] {
        let database = database(for: zone.lane)
        let zoneID = ckZoneID(for: zone)
        let records = try await fetchAllRecords(in: zoneID, database: database)

        let myName = await currentUserRecordName()
        // Resolve authors from the records we already fetched (the root record is in this
        // set) so we don't scan the zone a second time.
        let authors = await authorNames(from: records, database: database)

        return records
            .filter { $0.recordType == SpaceRecordType.spaceReflection }
            .compactMap { record -> SpaceReflection? in
                guard var reflection = SpaceRecordMapper.spaceReflection(
                    from: record,
                    isMine: isMine(record, lane: zone.lane, myUserRecordName: myName)
                ) else { return nil }
                if !reflection.isMine {
                    reflection.authorDisplayName = authors[record.creatorUserRecordID?.recordName ?? ""] ?? "A member"
                }
                return reflection
            }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    func createReflection(in zone: SpaceZoneRef, spaceID: String, title: String, promptText: String) async throws -> SpaceReflection {
        let database = database(for: zone.lane)
        let record = SpaceRecordMapper.makeReflectionRecord(
            zoneID: ckZoneID(for: zone),
            spaceID: spaceID,
            title: title,
            promptText: promptText
        )
        let saved = try await withRetry { try await database.save(record) }
        // We just authored it, so it is unambiguously mine — no need to infer from creator.
        guard let reflection = SpaceRecordMapper.spaceReflection(from: saved, isMine: true) else {
            throw SpaceError.syncFailed("Could not map the saved reflection")
        }
        return reflection
    }

    func fetchResponses(for reflection: SpaceReflection, in zone: SpaceZoneRef) async throws -> [SpaceResponse] {
        let database = database(for: zone.lane)
        let zoneID = ckZoneID(for: zone)
        let records = try await fetchAllRecords(in: zoneID, database: database)

        let myName = await currentUserRecordName()
        let authors = await authorNames(from: records, database: database)

        return records
            .filter { record in
                guard record.recordType == SpaceRecordType.response else { return false }
                let parentID = record.parent?.recordID.recordName
                    ?? (record[SpaceRecordField.reflectionID] as? String)
                return parentID == reflection.id
            }
            .compactMap { record -> SpaceResponse? in
                guard var response = SpaceRecordMapper.spaceResponse(
                    from: record,
                    isMine: isMine(record, lane: zone.lane, myUserRecordName: myName)
                ) else { return nil }
                if !response.isMine {
                    response.authorDisplayName = authors[record.creatorUserRecordID?.recordName ?? ""] ?? "A member"
                }
                return response
            }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    func createResponse(to reflection: SpaceReflection, body: String, in zone: SpaceZoneRef) async throws -> SpaceResponse {
        let database = database(for: zone.lane)
        let record = SpaceRecordMapper.makeResponseRecord(
            zoneID: ckZoneID(for: zone),
            reflectionID: reflection.id,
            body: body
        )
        let saved = try await withRetry { try await database.save(record) }
        guard let response = SpaceRecordMapper.spaceResponse(from: saved, isMine: true) else {
            throw SpaceError.syncFailed("Could not map the saved response")
        }
        return response
    }

    func updateResponse(id: String, in zone: SpaceZoneRef, body: String) async throws -> SpaceResponse {
        let database = database(for: zone.lane)
        let recordID = CKRecord.ID(recordName: id, zoneID: ckZoneID(for: zone))

        // Fetch-modify-save. On `serverRecordChanged`, re-fetch the latest and re-apply the
        // edit (last-writer-wins with the server record as base, plan §9). `withRetry`
        // covers transient network errors within each attempt.
        var conflictRetries = 0
        while true {
            do {
                let saved = try await withRetry { () -> CKRecord in
                    let record = try await database.record(for: recordID)
                    record[SpaceRecordField.body] = body as CKRecordValue
                    return try await database.save(record)
                }
                guard let response = SpaceRecordMapper.spaceResponse(from: saved, isMine: true) else {
                    throw SpaceError.syncFailed("Could not map the updated response")
                }
                return response
            } catch let error as CKError where error.code == .serverRecordChanged && conflictRetries < 2 {
                conflictRetries += 1
            }
        }
    }

    /// Deletes a record and any children parented to it. The hierarchy uses parent
    /// references with `action: .none` (required for CKShare), which do NOT cascade on the
    /// server — so deleting a reflection here also deletes its response records in the same
    /// operation rather than orphaning them. Deleting a response finds no children and
    /// removes just itself.
    func deleteRecord(id: String, in zone: SpaceZoneRef) async throws {
        let database = database(for: zone.lane)
        let zoneID = ckZoneID(for: zone)
        let records = try await fetchAllRecords(in: zoneID, database: database)

        var idsToDelete = [CKRecord.ID(recordName: id, zoneID: zoneID)]
        for record in records where record.parent?.recordID.recordName == id {
            idsToDelete.append(record.recordID)
        }

        try await withRetry {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: idsToDelete)
                operation.qualityOfService = .userInitiated
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        }
    }

    // MARK: - Subscriptions / background sync

    private static let privateSubscriptionID = "space-private-db-sub"
    private static let sharedSubscriptionID = "space-shared-db-sub"
    private static let privateTokenKey = "spacePrivateDBChangeToken"
    private static let sharedTokenKey = "spaceSharedDBChangeToken"

    func ensureSubscriptions() async throws {
        try await ensureDatabaseSubscription(id: Self.privateSubscriptionID, in: privateDB)
        try await ensureDatabaseSubscription(id: Self.sharedSubscriptionID, in: sharedDB)
    }

    private func ensureDatabaseSubscription(id: String, in database: CKDatabase) async throws {
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent push, no alert/badge
        subscription.notificationInfo = info
        do {
            _ = try await withRetry { try await database.save(subscription) }
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription with this fixed ID already exists — idempotent, ignore.
        }
    }

    func syncChanges() async throws -> Bool {
        let privateChanged = try await fetchDatabaseChanges(in: privateDB, tokenKey: Self.privateTokenKey)
        let sharedChanged = try await fetchDatabaseChanges(in: sharedDB, tokenKey: Self.sharedTokenKey)
        return privateChanged || sharedChanged
    }

    /// Advances (and persists) one database's change token. Returns whether any zone
    /// changed. On `changeTokenExpired` the token is cleared and we report `true` so the
    /// downstream fetch reloads from scratch rather than crashing.
    private func fetchDatabaseChanges(in database: CKDatabase, tokenKey: String) async throws -> Bool {
        let previousToken = loadChangeToken(key: tokenKey)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: previousToken)
            operation.fetchAllChanges = true

            var changedZoneCount = 0
            operation.recordZoneWithIDChangedBlock = { _ in changedZoneCount += 1 }
            // A space deleted/left on another device removes its zone — count that as a
            // change too, so the silent-push path reports .newData and the list refreshes.
            operation.recordZoneWithIDWasDeletedBlock = { _ in changedZoneCount += 1 }
            operation.recordZoneWithIDWasPurgedBlock = { _ in changedZoneCount += 1 }
            operation.changeTokenUpdatedBlock = { token in self.saveChangeToken(token, key: tokenKey) }
            operation.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let (token, _)):
                    self.saveChangeToken(token, key: tokenKey)
                    continuation.resume(returning: changedZoneCount > 0)
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                        self.saveChangeToken(nil, key: tokenKey)
                        continuation.resume(returning: true)
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            database.add(operation)
        }
    }

    private func loadChangeToken(key: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: CKServerChangeToken?, key: String) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    // Conflict handling note: the Space model is append-only (create + delete, no field
    // edits), so `serverRecordChanged` save conflicts don't arise — new records have unique
    // names and deletes don't conflict. If editing is added later, retry-once with the
    // server record as base goes here (plan §9).

    // MARK: - Authorship resolution

    /// The current user's record name in the Space container, cached after the first
    /// lookup. Used to decide `isMine` — compared by record *name*, never display name.
    private func currentUserRecordName() async -> String? {
        userRecordNameLock.lock()
        let cached = cachedUserRecordName
        userRecordNameLock.unlock()
        if let cached { return cached }

        let name = try? await container.userRecordID().recordName
        userRecordNameLock.lock()
        cachedUserRecordName = name
        userRecordNameLock.unlock()
        return name
    }

    /// Whether the current user authored `record`, resolved per lane.
    ///
    /// In the **private** DB the user owns the database, so a record they created shows a
    /// nil creator or the opaque `__defaultOwner__` (`CKCurrentUserDefaultName`) — treat
    /// those as mine. In the **shared** DB `__defaultOwner__` denotes the *share owner*
    /// (not the current participant), so it must never count as mine — match only the
    /// user's real record name, and fail closed otherwise. Fail-closed matters: `isMine`
    /// is the only guard before a delete, and CloudKit does not enforce per-record
    /// authorship in a shared zone (plan §11.2).
    private func isMine(_ record: CKRecord, lane: SpaceLane, myUserRecordName: String?) -> Bool {
        let creator = record.creatorUserRecordID?.recordName
        switch lane {
        case .privateDB:
            guard let creator else { return true }
            if creator == CKCurrentUserDefaultName { return true }
            if let myUserRecordName, creator == myUserRecordName { return true }
            return false
        case .sharedDB:
            guard let creator, let myUserRecordName else { return false }
            if creator == CKCurrentUserDefaultName { return false }
            return creator == myUserRecordName
        }
    }

    /// Maps participant record names → formatted display names, using the zone's `CKShare`.
    /// The root `Space` record is found in the already-fetched `records` (avoiding a second
    /// zone scan); only the share record itself is fetched. Best-effort: any failure yields
    /// an empty map and the caller falls back to "A member".
    private func authorNames(from records: [CKRecord], database: CKDatabase) async -> [String: String] {
        guard let root = records.first(where: { $0.recordType == SpaceRecordType.space }),
              let shareReference = root.share,
              let shareRecord = try? await database.record(for: shareReference.recordID),
              let share = shareRecord as? CKShare else {
            return [:]
        }
        let formatter = PersonNameComponentsFormatter()
        var map: [String: String] = [:]
        for participant in share.participants {
            guard let recordName = participant.userIdentity.userRecordID?.recordName,
                  let components = participant.userIdentity.nameComponents else { continue }
            let name = formatter.string(from: components)
            if !name.isEmpty { map[recordName] = name }
        }
        return map
    }

    // MARK: - Helpers

    private func ckZoneID(for zone: SpaceZoneRef) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone.zoneName, ownerName: zone.ownerName)
    }

    private func database(for lane: SpaceLane) -> CKDatabase {
        switch lane {
        case .privateDB: return privateDB
        case .sharedDB: return sharedDB
        }
    }

    // MARK: - Retry Logic with Exponential Backoff

    /// Retries only *transient* CloudKit failures (network/rate-limit/busy), honoring the
    /// server's `retryAfterSeconds` when present. Non-transient CKErrors (e.g. "already
    /// exists", quota, bad request) and `CancellationError` rethrow immediately — so we
    /// never back off on a permanent, expected outcome (was a ~6s launch penalty on the
    /// idempotent subscription save) and never blindly retry a non-idempotent write.
    private func withRetry<T: Sendable>(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError { throw error }
                guard let ckError = error as? CKError,
                      Self.isTransient(ckError),
                      attempt < maxRetries - 1 else {
                    throw error
                }
                let delay = ckError.retryAfterSeconds ?? baseDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }

    private static func isTransient(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }
}
