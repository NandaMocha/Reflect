import CloudKit
import Foundation

/// Ingests `PendingClipFeedback` records — guest answers the write endpoint (AC-015)
/// staged in the public database because the Clip itself cannot write to CloudKit — into
/// real `Answer` records in the owner's private shared zone, then deletes the pending
/// record. Auto-post per Decision 1 (app-clip-plan.md): no owner-approval step.
///
/// Called from the same sync tail as `SpaceMirrorService` (`SpaceCloudService.fetchChanges`).
/// The guest answer created here isn't visible in the public mirror until the **next**
/// sync pass re-publishes it (this pass's `reflections`/`answers` were fetched before
/// ingestion ran) — that latency is a known, documented trade-off (app-clip-plan.md
/// "Guest round trip" section), not a bug to fix here.
protocol SpaceClipIngestServiceProtocol: Sendable {
    /// For every owned, tokenized reflection in `reflectionIDs`, queries `PendingClipFeedback`
    /// by its `requestToken`, re-validates each pending answer (body length, `questionId`
    /// must be one of the reflection's current questions — the endpoint's own validation is
    /// never trusted alone), creates it as an `Answer` record with guest attribution, then
    /// deletes the pending record. A failure ingesting one pending record (or one
    /// reflection) does not stop the rest of the batch from being attempted. This only
    /// throws for a failure that blocks the whole batch (e.g. the precheck fetch itself);
    /// per-candidate failures are logged, not thrown.
    func ingestPendingFeedback(reflectionIDs: Set<String>, zone: SpaceZoneRef) async throws
}

enum SpaceClipIngestError: Error, LocalizedError {
    case notOwner
    case ingestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notOwner:
            return "Only the space owner's app ingests guest feedback."
        case .ingestFailed(let message):
            return "Couldn't ingest guest feedback: \(message)"
        }
    }
}

/// Concrete CloudKit implementation. Deliberately independent of `SpaceCloudService`
/// (same rationale as `SpaceMirrorService`) — it reads the public database's
/// `PendingClipFeedback` type and writes into the private/shared Space zone using the
/// shared `SpaceRecordMapper.makeAnswerRecord`, but owns its own CloudKit plumbing rather
/// than routing through `SpaceCloudServiceProtocol`.
final class SpaceClipIngestService: SpaceClipIngestServiceProtocol {

    // MARK: - Dependencies

    private let container = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")
    private let privateDB: CKDatabase
    private let sharedDB: CKDatabase
    private let publicDB: CKDatabase

    init() {
        privateDB = container.privateCloudDatabase
        sharedDB = container.sharedCloudDatabase
        publicDB = container.publicCloudDatabase
    }

    // MARK: - Ingest

    func ingestPendingFeedback(reflectionIDs: Set<String>, zone: SpaceZoneRef) async throws {
        // Never ingest into a zone the user doesn't own — the write endpoint stages
        // guest feedback for *some* owner to pick up; only that owner's own sync may
        // re-post it into their zone.
        guard zone.lane == .privateDB else { throw SpaceClipIngestError.notOwner }
        guard !reflectionIDs.isEmpty else { return }

        let database = database(for: zone.lane)
        let zoneID = CKRecordZone.ID(zoneName: zone.zoneName, ownerName: zone.ownerName)

        // Cheap batched precheck restricted to `requestToken`/`questionsJSON`, same
        // pattern `SpaceMirrorService.publishMirrors` uses, so a sync pass with no
        // tokenized reflections in it never pays for a public-DB query at all.
        let precheckRecords = try await fetchRecords(
            recordIDs: reflectionIDs.map { CKRecord.ID(recordName: $0, zoneID: zoneID) },
            database: database,
            desiredKeys: [SpaceRecordField.requestToken, SpaceRecordField.questionsJSON]
        )

        for (recordID, result) in precheckRecords {
            guard case .success(let record) = result,
                  record.recordType == SpaceRecordType.spaceReflection,
                  let token = record[SpaceRecordField.requestToken] as? String,
                  !token.isEmpty else { continue }

            let questionsJSON = record[SpaceRecordField.questionsJSON] as? String ?? "[]"
            let validQuestionIds = Set(SpaceQuestion.decodeJSON(questionsJSON).map { $0.id })

            do {
                try await ingest(
                    reflectionID: recordID.recordName,
                    token: token,
                    validQuestionIds: validQuestionIds,
                    zoneID: zoneID,
                    database: database
                )
            } catch {
                #if DEBUG
                print("[SpaceClipIngestService] ingest failed for \(recordID.recordName): \(error)")
                #endif
            }
        }
    }

    /// Ingests every pending record for one tokenized reflection's `token`.
    private func ingest(
        reflectionID: String,
        token: String,
        validQuestionIds: Set<String>,
        zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws {
        let pendingRecords = try await queryRecords(
            type: ClipMirrorRecordType.pendingClipFeedback,
            predicate: NSPredicate(format: "%K == %@", ClipMirrorField.requestToken, token)
        )
        guard !pendingRecords.isEmpty else { return }

        // Oldest-first: `Answer` has no stored `answerIndex` field — the mirror
        // (`SpaceMirrorService`) derives per-question ordering from each Answer's
        // CloudKit `creationDate` at publish time. Ingesting sequentially in submission
        // order (rather than concurrently, which would race creationDate assignment)
        // preserves the guest's original answer order for that later grouping.
        let ordered = pendingRecords.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }

        for pending in ordered {
            do {
                try await ingestOne(
                    pending: pending,
                    reflectionID: reflectionID,
                    validQuestionIds: validQuestionIds,
                    zoneID: zoneID,
                    database: database
                )
            } catch {
                #if DEBUG
                print("[SpaceClipIngestService] pending \(pending.recordID.recordName) failed: \(error)")
                #endif
            }
        }
    }

    /// Ingests a single `PendingClipFeedback` record: validate → save the `Answer` →
    /// delete the pending record, in that exact order. A crash between the two leaves
    /// the pending record in place; the deterministic `recordName` (`"guest-" +
    /// submissionId`) means the retry's save lands on the very same `Answer` record
    /// (treated as idempotent success below) and proceeds straight to the delete.
    private func ingestOne(
        pending: CKRecord,
        reflectionID: String,
        validQuestionIds: Set<String>,
        zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws {
        guard let questionId = pending[ClipMirrorField.questionId] as? String,
              let body = pending[ClipMirrorField.body] as? String,
              let guestId = pending[ClipMirrorField.guestId] as? String, !guestId.isEmpty else {
            // Malformed pending record — never trust the endpoint alone. Left in place
            // (not deleted) so a human can investigate rather than silently discarding
            // guest feedback.
            throw SpaceClipIngestError.ingestFailed("missing required fields")
        }
        let guestName = pending[ClipMirrorField.guestName] as? String

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty, trimmedBody.count <= Constants.Limits.spaceResponseMaxLength else {
            throw SpaceClipIngestError.ingestFailed("body invalid or too long")
        }
        guard validQuestionIds.contains(questionId) else {
            throw SpaceClipIngestError.ingestFailed("questionId not part of this request's current questions")
        }

        // "pcf-<submissionId>" -> "guest-<submissionId>": the deterministic Answer
        // recordName AC-012 owns. Must derive from the SAME submissionId the client
        // minted, never a fresh one, or a retried ingest would double-post.
        let submissionId = String(pending.recordID.recordName.dropFirst(ClipMirrorRecordName.pendingClipFeedbackPrefix.count))
        let answerRecordName = "guest-" + submissionId
        let answerRecord = SpaceRecordMapper.makeAnswerRecord(
            recordName: answerRecordName,
            zoneID: zoneID,
            reflectionID: reflectionID,
            questionId: questionId,
            text: trimmedBody,
            guestId: guestId,
            guestName: guestName
        )

        do {
            _ = try await database.save(answerRecord)
        } catch let error as CKError where Self.ckErrorMatches(error, recordID: answerRecord.recordID, code: .serverRecordChanged) {
            // The deterministic recordName already exists on the server — a previous,
            // interrupted ingest attempt already saved this exact Answer. Idempotent
            // success: fall through to delete the pending record below.
        }

        try await deletePendingRecord(pending.recordID)
    }

    /// Deletes a `PendingClipFeedback` record from the public database once its
    /// `Answer` has been saved. `.unknownItem` (already deleted — a raced concurrent
    /// ingest, or a retry after the delete itself already succeeded) is idempotent
    /// success, not a failure.
    private func deletePendingRecord(_ recordID: CKRecord.ID) async throws {
        do {
            _ = try await publicDB.deleteRecord(withID: recordID)
        } catch let error as CKError where Self.ckErrorMatches(error, recordID: recordID, code: .unknownItem) {
            // Already gone — fine.
        }
    }

    /// True when `error` reports `code` for `recordID`, whether it arrives as the
    /// top-level `CKError.code` (single-record `save`/`deleteRecord` convenience calls
    /// usually surface it this way) or nested in `partialErrorsByItemID` under
    /// `CKError.partialFailure` (the shape `CKModifyRecordsOperation`-backed calls can
    /// use instead). Checking only the top-level code silently stops matching if a future
    /// CloudKit/SDK change moves these calls onto the batch-operation path — the retry
    /// loop above would then treat every retry as a genuine failure, saving the pending
    /// record's `Answer` (or its delete) never completing (AC-012 review).
    private static func ckErrorMatches(_ error: CKError, recordID: CKRecord.ID, code: CKError.Code) -> Bool {
        if error.code == code { return true }
        guard error.code == .partialFailure,
              let itemErrors = error.partialErrorsByItemID else { return false }
        return (itemErrors[AnyHashable(recordID)] as? CKError)?.code == code
    }

    // MARK: - CloudKit primitives

    private func database(for lane: SpaceLane) -> CKDatabase {
        switch lane {
        case .privateDB: return privateDB
        case .sharedDB: return sharedDB
        }
    }

    /// Fetches a batch of records in a single `CKFetchRecordsOperation`, optionally
    /// restricted to `desiredKeys`. Per-record failures are reported in the returned
    /// per-ID `Result` rather than failing the whole batch — only an operation-level
    /// failure throws. Same pattern as `SpaceMirrorService.fetchRecords`, duplicated
    /// rather than shared per this service's deliberate independence from
    /// `SpaceMirrorService`/`SpaceCloudService`.
    private func fetchRecords(
        recordIDs: [CKRecord.ID],
        database: CKDatabase,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        guard !recordIDs.isEmpty else { return [:] }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord.ID: Result<CKRecord, Error>], Error>) in
            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            operation.desiredKeys = desiredKeys
            operation.qualityOfService = .utility

            var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
            operation.perRecordResultBlock = { recordID, result in
                results[recordID] = result
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: results)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    /// Queries the public database, following the query cursor to every page. Requires
    /// `requestToken`'s Queryable index (AC-H1). Same page-walking convention as
    /// `SpaceMirrorService.queryRecords`.
    private func queryRecords(type: String, predicate: NSPredicate) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        let query = CKQuery(recordType: type, predicate: predicate)
        var cursor = try await runQueryPage(CKQueryOperation(query: query), into: &records)

        while let currentCursor = cursor {
            cursor = try await runQueryPage(CKQueryOperation(cursor: currentCursor), into: &records)
        }

        return records
    }

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
}
