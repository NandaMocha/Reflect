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

    /// Queries a zone for its single root `Space` record.
    private func fetchRootSpaceRecord(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> CKRecord? {
        try await withRetry {
            let query = CKQuery(recordType: SpaceRecordType.space, predicate: NSPredicate(value: true))
            let results = try await database.records(matching: query, inZoneWith: zoneID)
            for (_, result) in results.matchResults {
                if case .success(let record) = result {
                    return record
                }
            }
            return nil
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

        // After acceptance the zone is mirrored into the SHARED database; fetch the
        // root record from there (not the private DB — we're not the owner).
        // `hierarchicalRootRecordID` is the non-deprecated iOS 17+ replacement for the
        // old `rootRecordID`; our share has no nested hierarchy so both point to the
        // same `Space` root record.
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw SpaceError.acceptFailed("Share metadata has no root record ID")
        }
        let rootRecord = try await withRetry { try await self.sharedDB.record(for: rootRecordID) }
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

    // MARK: - Helpers

    private func database(for lane: SpaceLane) -> CKDatabase {
        switch lane {
        case .privateDB: return privateDB
        case .sharedDB: return sharedDB
        }
    }

    // MARK: - Retry Logic with Exponential Backoff
    // Mirrors CloudSyncService.uploadWithRetry's shape (same backoff curve: 1s, 2s, 4s).

    private func withRetry<T: Sendable>(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }
}
