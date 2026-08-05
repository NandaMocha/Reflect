import CloudKit
import Foundation

/// Publishes (and revokes) the public-DB "Clip mirror" of an owned, tokenized
/// `SpaceReflection` — the read-only `MirroredRequest`/`MirroredAnswer` records the App
/// Clip's `ClipSpaceRepository` (AC-020) reads by `requestToken`, since the Clip cannot
/// see the private Space zone directly.
///
/// Writes go through the *public* database under the current (owner) user's account —
/// AC-H1 grants the security role that lets an authenticated user create these record
/// types. Never call this for a zone the user doesn't own; `publishMirror` guards that.
protocol SpaceMirrorServiceProtocol {
    /// Upserts the `MirroredRequest` + one `MirroredAnswer` per current `Answer` for a
    /// single tokenized reflection, diffed against whatever is already published for its
    /// token (unchanged records are left alone; answers whose source `Answer` no longer
    /// exists are deleted as orphans).
    ///
    /// Throws `SpaceMirrorError.noRequestToken` (not really a failure — the caller's
    /// sync hook should treat it as "nothing to publish") when the reflection has never
    /// had `ensureRequestToken` called on it.
    func publishMirror(reflectionID: String, zone: SpaceZoneRef) async throws

    /// Deletes the `TokenIndex` plus every `MirroredRequest`/`MirroredAnswer` published
    /// for `token`. Idempotent — revoking an already-revoked (or never-published) token
    /// is not an error.
    func revokeMirror(for token: String) async throws
}

enum SpaceMirrorError: Error, LocalizedError {
    case notOwner
    case reflectionNotFound
    case noRequestToken
    case publishFailed(String)
    case revokeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notOwner:
            return "Only the space owner can publish a guest-feedback mirror."
        case .reflectionNotFound:
            return "That feedback request could not be found."
        case .noRequestToken:
            return "This request has no guest-feedback link yet."
        case .publishFailed(let message):
            return "Couldn't publish the guest-feedback mirror: \(message)"
        case .revokeFailed(let message):
            return "Couldn't revoke the guest-feedback mirror: \(message)"
        }
    }
}

/// Concrete CloudKit implementation. Deliberately independent of `SpaceCloudService`
/// (rather than routing through `SpaceCloudServiceProtocol`) — it reads/writes the
/// public database's `MirroredRequest`/`MirroredAnswer`/`TokenIndex` types, which are
/// outside that protocol's private/shared-DB Space hierarchy, and it needs a full,
/// tokenless snapshot of one zone rather than the incremental change-token bookkeeping
/// `SpaceCloudService.fetchChanges` owns.
final class SpaceMirrorService: SpaceMirrorServiceProtocol {

    // MARK: - Dependencies

    private let container = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")
    // Non-lazy: `publishMirrorsIfOwned`, `publishMirrorIfOwned`, and `revokeMirrorsIfOwned`
    // each spawn their own `Task.detached` against this one shared instance, so first
    // access can race across concurrent tasks. `lazy` stored-property initialization is
    // not thread-safe; a plain `let` sidesteps the race entirely.
    private let privateDB: CKDatabase
    private let publicDB: CKDatabase

    init() {
        privateDB = container.privateCloudDatabase
        publicDB = container.publicCloudDatabase
    }

    // MARK: - Publish

    func publishMirror(reflectionID: String, zone: SpaceZoneRef) async throws {
        // Never mirror a Space the user doesn't own — the public mirror is only ever a
        // projection of the owner's private-DB data.
        guard zone.lane == .privateDB else { throw SpaceMirrorError.notOwner }

        let zoneID = CKRecordZone.ID(zoneName: zone.zoneName, ownerName: zone.ownerName)

        // Cheap pre-check: fetch just this one reflection record (not a full zone
        // download) and bail out on `.noRequestToken` before paying for
        // `fetchAllRecords`'s tokenless zone-changes fetch, which pulls down every
        // record — including every image CKAsset — in the zone. Callers publish
        // per-reflection on every sync pass regardless of whether that reflection is
        // actually tokenized, so this check has to be cheap for the common
        // not-yet-shared case.
        let reflectionRecordID = CKRecord.ID(recordName: reflectionID, zoneID: zoneID)
        let precheckRecord: CKRecord
        do {
            precheckRecord = try await privateDB.record(for: reflectionRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            throw SpaceMirrorError.reflectionNotFound
        } catch {
            throw SpaceMirrorError.publishFailed(error.localizedDescription)
        }
        guard precheckRecord.recordType == SpaceRecordType.spaceReflection else {
            throw SpaceMirrorError.reflectionNotFound
        }
        guard let precheckToken = precheckRecord[SpaceRecordField.requestToken] as? String,
              !precheckToken.isEmpty else {
            throw SpaceMirrorError.noRequestToken
        }

        let records: [CKRecord]
        do {
            records = try await fetchAllRecords(in: zoneID)
        } catch {
            throw SpaceMirrorError.publishFailed(error.localizedDescription)
        }

        guard let reflectionRecord = records.first(where: {
            $0.recordType == SpaceRecordType.spaceReflection && $0.recordID.recordName == reflectionID
        }) else {
            throw SpaceMirrorError.reflectionNotFound
        }

        guard let token = reflectionRecord[SpaceRecordField.requestToken] as? String, !token.isEmpty else {
            throw SpaceMirrorError.noRequestToken
        }

        let title = reflectionRecord[SpaceRecordField.title] as? String ?? ""
        let note = reflectionRecord[SpaceRecordField.note] as? String
        let questionsJSON = reflectionRecord[SpaceRecordField.questionsJSON] as? String ?? "[]"
        let thumbnail = Self.thumbnailAsset(from: reflectionRecord)

        let answerRecords = records.filter {
            $0.recordType == SpaceRecordType.answer && $0.parent?.recordID.recordName == reflectionID
        }
        let authorNames = await resolveAuthorNames(records: records)

        let desiredRequestRecord = SpaceRecordMapper.makeMirroredRequestRecord(
            token: token,
            title: title,
            note: note,
            questionsJSON: questionsJSON,
            thumbnail: thumbnail
        )
        let desiredAnswerRecords = Self.makeMirroredAnswerRecords(
            from: answerRecords,
            token: token,
            authorNames: authorNames
        )

        do {
            try await diffAndSave(
                requestRecord: desiredRequestRecord,
                answerRecords: desiredAnswerRecords,
                token: token
            )
        } catch {
            throw SpaceMirrorError.publishFailed(error.localizedDescription)
        }
    }

    /// Builds the desired `MirroredAnswer` records, ordered per-question so `answerIndex`
    /// matches the grouping `ClipSpaceRepository` (AC-020) reconstructs on the read side.
    private static func makeMirroredAnswerRecords(
        from answerRecords: [CKRecord],
        token: String,
        authorNames: [String: String]
    ) -> [CKRecord] {
        let grouped = Dictionary(grouping: answerRecords) { record in
            record[SpaceRecordField.questionId] as? String ?? ""
        }
        var result: [CKRecord] = []
        for (_, group) in grouped {
            let ordered = group.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            for (index, record) in ordered.enumerated() {
                guard let questionId = record[SpaceRecordField.questionId] as? String,
                      let text = record[SpaceRecordField.text] as? String else { continue }
                let guestId = record[SpaceRecordField.guestId] as? String
                let displayName = Self.authorDisplayName(for: record, guestId: guestId, authorNames: authorNames)
                result.append(SpaceRecordMapper.makeMirroredAnswerRecord(
                    token: token,
                    sourceAnswerRecordName: record.recordID.recordName,
                    questionId: questionId,
                    answerIndex: index,
                    authorDisplayName: displayName,
                    text: text,
                    guestId: guestId
                ))
            }
        }
        return result
    }

    /// A guest answer's byline is its own `guestName`; a member answer's byline is
    /// resolved the same way the thread does (self-registered profile, then CKShare
    /// identity name), falling back to "A member" — the established fallback string
    /// used across the Space feature (`SpaceMember.displayTitle`, `SpaceCloudService`).
    private static func authorDisplayName(for record: CKRecord, guestId: String?, authorNames: [String: String]) -> String {
        if let guestId, !guestId.isEmpty {
            let guestName = record[SpaceRecordField.guestName] as? String
            return (guestName?.isEmpty == false ? guestName : nil) ?? "A member"
        }
        let creatorName = record.creatorUserRecordID?.recordName
        return creatorName.flatMap { authorNames[$0] } ?? "A member"
    }

    /// Best-effort thumbnail passthrough — reuses the reflection's already-downloaded
    /// image asset file rather than re-encoding, per the ticket's "if cheap" scope.
    private static func thumbnailAsset(from reflectionRecord: CKRecord) -> CKAsset? {
        guard let asset = reflectionRecord[SpaceRecordField.imageAsset] as? CKAsset,
              let fileURL = asset.fileURL else { return nil }
        return CKAsset(fileURL: fileURL)
    }

    /// Author display names for every record's creator, resolved with the same
    /// precedence `SpaceCloudService.authorNames` uses: self-registered `MemberProfile`
    /// first (visible to every participant), then the `CKShare` participant's identity
    /// name where CloudKit happens to expose it. Best-effort — an unresolved author is
    /// simply absent from the map and `authorDisplayName(for:guestId:authorNames:)` falls
    /// back to "A member".
    private func resolveAuthorNames(records: [CKRecord]) async -> [String: String] {
        var map: [String: String] = [:]
        for record in records {
            if let profile = SpaceRecordMapper.memberProfile(from: record) {
                map[profile.memberRecordName] = profile.displayName
            }
        }

        guard let root = records.first(where: { $0.recordType == SpaceRecordType.space }),
              let shareReference = root.share,
              let shareRecord = try? await privateDB.record(for: shareReference.recordID),
              let share = shareRecord as? CKShare else {
            return map
        }
        let formatter = PersonNameComponentsFormatter()
        for participant in share.participants {
            guard let recordName = participant.userIdentity.userRecordID?.recordName,
                  map[recordName] == nil,
                  let components = participant.userIdentity.nameComponents else { continue }
            let name = formatter.string(from: components)
            if !name.isEmpty { map[recordName] = name }
        }
        return map
    }

    /// Diffs the desired mirror records against whatever is already published for
    /// `token`: unchanged records are skipped, changed/new records are saved, and
    /// existing `MirroredAnswer`s whose source `Answer` no longer exists are deleted.
    private func diffAndSave(requestRecord: CKRecord, answerRecords: [CKRecord], token: String) async throws {
        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        let existingRequest: CKRecord?
        do {
            existingRequest = try await publicDB.record(for: requestRecord.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Not published yet — first publish for this token.
            existingRequest = nil
        }
        if existingRequest == nil || !Self.mirroredRequestUnchanged(existingRequest!, requestRecord) {
            recordsToSave.append(requestRecord)
        }

        let existingAnswers: [CKRecord]
        do {
            existingAnswers = try await queryRecords(
                type: ClipMirrorRecordType.mirroredAnswer,
                predicate: NSPredicate(format: "%K == %@", ClipMirrorField.requestToken, token)
            )
        } catch let error as CKError where error.code == .invalidArguments || error.code == .unknownItem {
            // Query surface not provisioned yet (pre-AC-H1) or nothing indexed — same
            // "nothing published yet" case `revokeMirror` treats as non-fatal below.
            // Deliberately skip the orphan-delete step this pass rather than treating
            // every existing MirroredAnswer as gone.
            existingAnswers = []
        }
        let existingByName = Dictionary(uniqueKeysWithValues: existingAnswers.map { ($0.recordID.recordName, $0) })
        let desiredNames = Set(answerRecords.map { $0.recordID.recordName })

        for desired in answerRecords {
            if let existing = existingByName[desired.recordID.recordName],
               Self.mirroredAnswerUnchanged(existing, desired) {
                continue
            }
            recordsToSave.append(desired)
        }
        for (name, existing) in existingByName where !desiredNames.contains(name) {
            recordIDsToDelete.append(existing.recordID)
        }

        guard !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty else { return }
        try await modifyPublic(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
    }

    private static func mirroredRequestUnchanged(_ existing: CKRecord, _ desired: CKRecord) -> Bool {
        existing[ClipMirrorField.title] as? String == desired[ClipMirrorField.title] as? String &&
        existing[ClipMirrorField.note] as? String == desired[ClipMirrorField.note] as? String &&
        existing[ClipMirrorField.questionsJSON] as? String == desired[ClipMirrorField.questionsJSON] as? String
    }

    private static func mirroredAnswerUnchanged(_ existing: CKRecord, _ desired: CKRecord) -> Bool {
        existing[ClipMirrorField.questionId] as? String == desired[ClipMirrorField.questionId] as? String &&
        existing[ClipMirrorField.answerIndex] as? Int == desired[ClipMirrorField.answerIndex] as? Int &&
        existing[ClipMirrorField.authorDisplayName] as? String == desired[ClipMirrorField.authorDisplayName] as? String &&
        existing[ClipMirrorField.text] as? String == desired[ClipMirrorField.text] as? String &&
        existing[ClipMirrorField.guestId] as? String == desired[ClipMirrorField.guestId] as? String
    }

    // MARK: - Revoke

    func revokeMirror(for token: String) async throws {
        var recordIDsToDelete: [CKRecord.ID] = [
            CKRecord.ID(recordName: ClipMirrorRecordName.tokenIndex(for: token)),
            CKRecord.ID(recordName: SpaceMirrorRecordName.mirroredRequest(for: token))
        ]

        do {
            let mirroredAnswers = try await queryRecords(
                type: ClipMirrorRecordType.mirroredAnswer,
                predicate: NSPredicate(format: "%K == %@", ClipMirrorField.requestToken, token)
            )
            recordIDsToDelete.append(contentsOf: mirroredAnswers.map { $0.recordID })
        } catch let error as CKError where error.code == .invalidArguments || error.code == .unknownItem {
            // Query surface not provisioned yet (pre-AC-H1) or nothing indexed — fall
            // through and still attempt the deterministic-name deletes below.
        } catch {
            throw SpaceMirrorError.revokeFailed(error.localizedDescription)
        }

        do {
            try await modifyPublic(recordsToSave: [], recordIDsToDelete: recordIDsToDelete)
        } catch {
            throw SpaceMirrorError.revokeFailed(error.localizedDescription)
        }
    }

    // MARK: - CloudKit primitives

    /// Fetches every record currently in `zoneID` via a one-shot, tokenless zone-changes
    /// operation. Same index-free technique `SpaceCloudService.fetchAllRecords` uses
    /// (`CKQuery` needs the `recordName` system field marked Queryable, which
    /// auto-created Development schema leaves off) — duplicated here rather than shared
    /// because this service intentionally has no dependency on `SpaceCloudService`.
    private func fetchAllRecords(in zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = nil
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )
            operation.fetchAllChanges = true
            operation.qualityOfService = .utility

            var records: [CKRecord] = []
            var zoneError: Error?
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { records.append(record) }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                if case .failure(let error) = result { zoneError = error }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                if let zoneError {
                    continuation.resume(throwing: zoneError)
                    return
                }
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            privateDB.add(operation)
        }
    }

    /// Queries the public database, following the query cursor to every page. Requires
    /// the field's Queryable index (AC-H1) — until that Console setup lands this throws,
    /// which callers here treat as "nothing to diff against yet" rather than a hard
    /// failure.
    ///
    /// CloudKit caps a single query response (~100 records) and returns a cursor for the
    /// rest — the earlier single-page version silently dropped everything past page 1,
    /// which in `revokeMirror` left later `MirroredAnswer` pages live and publicly
    /// readable after "revocation", and in `diffAndSave` broke orphan detection past
    /// page 1. Same page-walking convention as `CloudSyncService.forEachPage`.
    private func queryRecords(type: String, predicate: NSPredicate) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        let query = CKQuery(recordType: type, predicate: predicate)
        var cursor = try await runQueryPage(CKQueryOperation(query: query), into: &records)

        while let currentCursor = cursor {
            cursor = try await runQueryPage(CKQueryOperation(cursor: currentCursor), into: &records)
        }

        return records
    }

    /// Runs one `CKQueryOperation` page against the public database, appends its
    /// matches to `records`, and returns the cursor for the next page (nil when this was
    /// the last page).
    private func runQueryPage(
        _ operation: CKQueryOperation,
        into records: inout [CKRecord]
    ) async throws -> CKQueryOperation.Cursor? {
        let (pageRecords, cursor) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<([CKRecord], CKQueryOperation.Cursor?), Error>) in
            var pageRecords: [CKRecord] = []
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result { pageRecords.append(record) }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (pageRecords, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            publicDB.add(operation)
        }
        records.append(contentsOf: pageRecords)
        return cursor
    }

    /// One `CKModifyRecordsOperation` against the public database, batched to CloudKit's
    /// ≤400-records-per-operation limit.
    private func modifyPublic(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID]) async throws {
        let saveBatches = recordsToSave.chunked(into: 400)
        let deleteBatches = recordIDsToDelete.chunked(into: 400)
        let batchCount = max(saveBatches.count, deleteBatches.count, recordsToSave.isEmpty && recordIDsToDelete.isEmpty ? 0 : 1)

        for index in 0..<batchCount {
            let saves = index < saveBatches.count ? saveBatches[index] : []
            let deletes = index < deleteBatches.count ? deleteBatches[index] : []
            guard !saves.isEmpty || !deletes.isEmpty else { continue }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKModifyRecordsOperation(recordsToSave: saves, recordIDsToDelete: deletes)
                operation.savePolicy = .allKeys
                operation.qualityOfService = .utility
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: ())
                    case .failure(let error as CKError) where error.code == .unknownItem:
                        // Deleting a record already gone (revoked twice, raced with
                        // another delete) — idempotent, not a failure.
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                publicDB.add(operation)
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
