import Foundation
import CloudKit
import Combine

final class CloudSyncService: CloudSyncServiceProtocol {
    private lazy var container: CKContainer = {
        // Use default container as a safer alternative
        // Custom container identifier requires proper entitlements setup
        return CKContainer.default()
    }()

    private lazy var database: CKDatabase = {
        return container.privateCloudDatabase
    }()

    private let syncStatusSubject = CurrentValueSubject<SyncStatus, Never>(.idle)

    var syncStatus: SyncStatus {
        syncStatusSubject.value
    }

    var syncStatusPublisher: AnyPublisher<SyncStatus, Never> {
        syncStatusSubject.eraseToAnyPublisher()
    }

    init() {
        // Lazy properties will be initialized on first access
    }

    /// CloudKit record types written by `backup` and read back by `restore`. These are our
    /// own hand-rolled types — the app does not use SwiftData's CloudKit mirroring
    /// (`cloudKitDatabase: .none` in `ReflectApp`), so nothing here is `CD_`-prefixed.
    private enum RecordType {
        static let learning = "CKLearning"
        static let reflection = "CKReflection"
        static let image = "CKImageAttachment"
        static let voice = "CKVoiceRecording"
        static let video = "CKVideoAttachment"
        static let insight = "CKInsight"

        static let all = [learning, reflection, image, voice, video, insight]
    }

    func checkCloudAvailability() async -> CloudAvailability {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .temporarilyUnavailable
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .temporarilyUnavailable
            }
        } catch {
            return .networkUnavailable
        }
    }

    func checkExistingData() async throws -> CloudDataSummary? {
        syncStatusSubject.send(.checking)

        let availability = await checkCloudAvailability()
        guard availability == .available else {
            syncStatusSubject.send(.idle)
            return nil
        }

        do {
            let learningsCount = try await fetchRecordCount(recordType: RecordType.learning)
            let reflectionsCount = try await fetchRecordCount(recordType: RecordType.reflection)
            let imagesCount = try await fetchRecordCount(recordType: RecordType.image)
            let voiceNotesCount = try await fetchRecordCount(recordType: RecordType.voice)
            let insightsCount = try await fetchRecordCount(recordType: RecordType.insight)

            // Bail before asking for the backup date — on a device that has never backed up
            // there is no schema to sort by, and that query would fail an otherwise
            // perfectly correct "there is nothing here" answer.
            if learningsCount == 0 && reflectionsCount == 0 && insightsCount == 0 {
                syncStatusSubject.send(.idle)
                return nil
            }

            let lastBackupDate = try await fetchLastBackupDate()

            syncStatusSubject.send(.idle)

            return CloudDataSummary(
                learningsCount: learningsCount,
                reflectionsCount: reflectionsCount,
                imagesCount: imagesCount,
                voiceNotesCount: voiceNotesCount,
                insightsCount: insightsCount,
                lastBackupDate: lastBackupDate
            )
        } catch {
            syncStatusSubject.send(.failed(error.localizedDescription))
            throw error
        }
    }

    func backup(
        learnings: [Learning],
        reflections: [Reflection],
        insights: [CloudInsightRecord]
    ) async throws -> SyncResult {
        syncStatusSubject.send(.syncing(progress: 0))

        let availability = await checkCloudAvailability()
        guard availability == .available else {
            let error = SyncError.iCloudAccountNotFound
            syncStatusSubject.send(.failed(error.localizedDescription ?? "iCloud unavailable"))
            throw error
        }

        var errors: [SyncError] = []
        var itemsSynced = 0
        let totalItems = learnings.count + reflections.count + insights.count

        do {
            // Delete existing data first
            try await deleteAllCloudData()

            // Upload learnings concurrently in batches
            let batchSize = 5
            for batchStart in stride(from: 0, to: learnings.count, by: batchSize) {
                let batch = Array(learnings[batchStart..<min(batchStart + batchSize, learnings.count)])

                let batchResults = await uploadLearningsConcurrently(batch)
                for result in batchResults {
                    if result.success {
                        itemsSynced += 1
                    } else {
                        errors.append(result.error)
                    }
                }

                let progress = Double(itemsSynced) / Double(totalItems)
                syncStatusSubject.send(.syncing(progress: progress))
            }

            // Upload reflections with attachments
            for reflection in reflections {
                do {
                    try await uploadWithRetry(maxRetries: 3) {
                        try await self.uploadReflection(reflection)
                    }
                    itemsSynced += 1
                    let progress = Double(itemsSynced) / Double(totalItems)
                    syncStatusSubject.send(.syncing(progress: progress))
                } catch {
                    errors.append(.uploadFailed("Reflection: \(reflection.title)"))
                }
            }

            // Upload insights. Plain value types, no assets — the simplest record type in
            // the schema, mirrored via `makeRecord(_: CloudInsightRecord)` below.
            for insight in insights {
                do {
                    try await uploadWithRetry(maxRetries: 3) {
                        _ = try await self.database.save(Self.makeRecord(insight))
                    }
                    itemsSynced += 1
                    let progress = Double(itemsSynced) / Double(totalItems)
                    syncStatusSubject.send(.syncing(progress: progress))
                } catch {
                    errors.append(.uploadFailed("Insight"))
                }
            }

            let result = SyncResult(
                success: errors.isEmpty,
                itemsSynced: itemsSynced,
                errors: errors,
                completedAt: Date()
            )

            if result.success {
                syncStatusSubject.send(.completed(Date()))
            } else {
                syncStatusSubject.send(.failed("Backup completed with \(errors.count) errors"))
            }

            return result
        } catch {
            syncStatusSubject.send(.failed(error.localizedDescription))
            throw error
        }
    }

    func restore(
        applying apply: @Sendable @MainActor (CloudBackupSnapshot) throws -> Int
    ) async throws -> SyncResult {
        syncStatusSubject.send(.syncing(progress: 0))

        let availability = await checkCloudAvailability()
        guard availability == .available else {
            let error = SyncError.iCloudAccountNotFound
            syncStatusSubject.send(.failed(error.localizedDescription ?? "iCloud unavailable"))
            throw error
        }

        do {
            let snapshot = try await fetchBackupSnapshot()

            // Never wipe local data for an empty download. `apply` deletes the local store
            // before inserting, so restoring an empty snapshot would destroy everything and
            // still report success. If the backup came back empty (deleted elsewhere, or a
            // transient fetch failure), bail out and leave the local store untouched.
            guard !snapshot.isEmpty else {
                let error = SyncError.emptyBackup
                syncStatusSubject.send(.failed(error.localizedDescription ?? "No backup found"))
                throw error
            }

            // The download is the slow half; the write is fast but not instant, so the bar
            // parks at 90% rather than jumping to done before anything is on disk.
            syncStatusSubject.send(.syncing(progress: 0.9))
            let itemsRestored = try await apply(snapshot)

            syncStatusSubject.send(.completed(Date()))
            return SyncResult(
                success: true,
                itemsSynced: itemsRestored,
                errors: [],
                completedAt: Date()
            )
        } catch {
            syncStatusSubject.send(.failed(error.localizedDescription))
            throw error
        }
    }

    /// Downloads every backed-up record and decodes it into value types.
    ///
    /// Each record type is a separate query; progress is reported per completed type so the
    /// UI moves during what is otherwise a long silent wait.
    private func fetchBackupSnapshot() async throws -> CloudBackupSnapshot {
        var snapshot = CloudBackupSnapshot()

        let learningRecords = try await fetchAllRecords(recordType: RecordType.learning)
        snapshot.learnings = learningRecords.compactMap(Self.decodeLearning)
        syncStatusSubject.send(.syncing(progress: 0.15))

        let reflectionRecords = try await fetchAllRecords(recordType: RecordType.reflection)
        snapshot.reflections = reflectionRecords.compactMap(Self.decodeReflection)
        syncStatusSubject.send(.syncing(progress: 0.35))

        let imageRecords = try await fetchAllRecords(recordType: RecordType.image)
        snapshot.images = imageRecords.compactMap(Self.decodeImage)
        syncStatusSubject.send(.syncing(progress: 0.55))

        let voiceRecords = try await fetchAllRecords(recordType: RecordType.voice)
        snapshot.voiceRecordings = voiceRecords.compactMap(Self.decodeVoice)
        syncStatusSubject.send(.syncing(progress: 0.7))

        let videoRecords = try await fetchAllRecords(recordType: RecordType.video)
        snapshot.videos = videoRecords.compactMap(Self.decodeVideo)
        syncStatusSubject.send(.syncing(progress: 0.82))

        let insightRecords = try await fetchAllRecords(recordType: RecordType.insight)
        snapshot.insights = insightRecords.compactMap(Self.decodeInsight)

        return snapshot
    }

    func deleteAllCloudData() async throws {
        for recordType in RecordType.all {
            // Collect IDs across every page before deleting. `backup` clears the cloud
            // before re-uploading, so a partial sweep here would leave stale records behind
            // and hand the next restore a pile of duplicates.
            var recordIDs: [CKRecord.ID] = []

            try await forEachPage(recordType: recordType, desiredKeys: []) { matchResults in
                recordIDs.append(contentsOf: matchResults.map(\.0))
            }

            for recordID in recordIDs {
                try await database.deleteRecord(withID: recordID)
            }
        }
    }

    // MARK: - Private Methods

    /// Counts records of one type, following query cursors.
    ///
    /// `desiredKeys: []` keeps this to record IDs — counting must not drag down every image
    /// and audio asset in the backup.
    private func fetchRecordCount(recordType: String) async throws -> Int {
        var count = 0

        try await forEachPage(recordType: recordType, desiredKeys: []) { matchResults in
            count += matchResults.count
        }

        return count
    }

    /// Fetches every record of one type, following query cursors.
    ///
    /// CloudKit caps a single query response (100 records by default) and returns a cursor
    /// for the rest. Reading only the first page is why the old count silently plateaued on
    /// large backups — and would have restored only a fraction of them.
    private func fetchAllRecords(recordType: String) async throws -> [CKRecord] {
        var records: [CKRecord] = []

        try await forEachPage(recordType: recordType, desiredKeys: nil) { matchResults in
            for (_, result) in matchResults {
                // A per-record failure shouldn't abort the whole restore — skip it and keep
                // going, so one corrupt row can't strand the other 400.
                if case .success(let record) = result {
                    records.append(record)
                }
            }
        }

        return records
    }

    /// Walks every page of a `recordType` query, invoking `handlePage` per page.
    ///
    /// A missing record type means the user has simply never run a backup (CloudKit only
    /// creates the schema on first write), so that is reported as "no records" rather than
    /// as an error.
    private func forEachPage(
        recordType: String,
        predicate: NSPredicate = NSPredicate(value: true),
        desiredKeys: [CKRecord.FieldKey]?,
        handlePage: ([(CKRecord.ID, Result<CKRecord, Error>)]) -> Void
    ) async throws {
        var cursor: CKQueryOperation.Cursor?

        do {
            let firstPage = try await uploadWithRetry(maxRetries: 2) {
                let query = CKQuery(recordType: recordType, predicate: predicate)
                return try await self.database.records(matching: query, desiredKeys: desiredKeys)
            }
            handlePage(firstPage.matchResults)
            cursor = firstPage.queryCursor
        } catch let error as CKError where error.code == .unknownItem {
            return
        }

        while let currentCursor = cursor {
            let page = try await uploadWithRetry(maxRetries: 2) {
                try await self.database.records(
                    continuingMatchFrom: currentCursor,
                    desiredKeys: desiredKeys
                )
            }
            handlePage(page.matchResults)
            cursor = page.queryCursor
        }
    }

    private func fetchLastBackupDate() async throws -> Date? {
        return try await uploadWithRetry(maxRetries: 2) {
            let query = CKQuery(recordType: RecordType.learning, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

            let results = try await self.database.records(matching: query, desiredKeys: nil, resultsLimit: 1)

            if let firstResult = results.matchResults.first,
               case .success(let record) = firstResult.1 {
                return record.modificationDate
            }

            return nil
        }
    }

    // MARK: - Record Decoding

    /// Reads a `CKAsset` field back into memory.
    ///
    /// CloudKit stages assets as files in a temporary location; if that file is gone the
    /// attachment comes back without its payload rather than failing the restore.
    private static func assetData(_ record: CKRecord, key: String) -> Data? {
        guard let asset = record[key] as? CKAsset, let fileURL = asset.fileURL else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    private static func localID(_ record: CKRecord, key: String = "localID") -> UUID? {
        guard let raw = record[key] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private static func decodeLearning(_ record: CKRecord) -> CloudLearningRecord? {
        guard let id = localID(record) else { return nil }

        return CloudLearningRecord(
            id: id,
            title: record["title"] as? String ?? "",
            descriptionText: record["descriptionText"] as? String,
            colorHex: record["colorHex"] as? String ?? "3AAFA9",
            iconName: record["iconName"] as? String ?? "book.fill",
            sortOrder: record["sortOrder"] as? Int ?? 0,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        )
    }

    private static func decodeReflection(_ record: CKRecord) -> CloudReflectionRecord? {
        guard let id = localID(record) else { return nil }

        return CloudReflectionRecord(
            id: id,
            learningID: localID(record, key: "learningID"),
            title: record["title"] as? String ?? "",
            contentData: assetData(record, key: "contentData"),
            plainTextContent: record["plainTextContent"] as? String ?? "",
            isFavorite: record["isFavorite"] as? Bool ?? false,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        )
    }

    private static func decodeImage(_ record: CKRecord) -> CloudImageRecord? {
        // An attachment with no parent has nowhere to land, so it is dropped rather than
        // restored as an orphan.
        guard let id = localID(record),
              let reflectionID = localID(record, key: "reflectionID") else { return nil }

        return CloudImageRecord(
            id: id,
            reflectionID: reflectionID,
            imageData: assetData(record, key: "imageAsset"),
            thumbnailData: assetData(record, key: "thumbnailAsset"),
            caption: record["caption"] as? String,
            sortOrder: record["sortOrder"] as? Int ?? 0,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date()
        )
    }

    private static func decodeVoice(_ record: CKRecord) -> CloudVoiceRecord? {
        guard let id = localID(record),
              let reflectionID = localID(record, key: "reflectionID") else { return nil }

        return CloudVoiceRecord(
            id: id,
            reflectionID: reflectionID,
            audioData: assetData(record, key: "audioAsset"),
            transcription: record["transcription"] as? String,
            language: record["language"] as? String ?? "en-US",
            duration: record["duration"] as? TimeInterval ?? 0,
            waveformSamples: (record["waveformSamples"] as? [NSNumber])?.map(\.floatValue) ?? [],
            sortOrder: record["sortOrder"] as? Int ?? 0,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date()
        )
    }

    private static func decodeInsight(_ record: CKRecord) -> CloudInsightRecord? {
        guard let id = localID(record) else { return nil }

        return CloudInsightRecord(
            id: id,
            text: record["text"] as? String ?? "",
            typeRawValue: record["typeRawValue"] as? String ?? "note",
            followUp: record["followUp"] as? String ?? "",
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        )
    }

    private static func decodeVideo(_ record: CKRecord) -> CloudVideoRecord? {
        guard let id = localID(record),
              let reflectionID = localID(record, key: "reflectionID") else { return nil }

        return CloudVideoRecord(
            id: id,
            reflectionID: reflectionID,
            videoData: assetData(record, key: "videoAsset"),
            thumbnailData: assetData(record, key: "thumbnailAsset"),
            caption: record["caption"] as? String,
            duration: record["duration"] as? TimeInterval ?? 0,
            sortOrder: record["sortOrder"] as? Int ?? 0,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date()
        )
    }

    // MARK: - Concurrent Upload Methods

    private struct UploadResult {
        let success: Bool
        let error: SyncError
    }

    private func uploadLearningsConcurrently(_ learnings: [Learning]) async -> [UploadResult] {
        return await withTaskGroup(of: UploadResult.self) { group in
            for learning in learnings {
                group.addTask {
                    do {
                        try await self.uploadWithRetry(maxRetries: 3) {
                            try await self.uploadLearning(learning)
                        }
                        return UploadResult(success: true, error: .uploadFailed(""))
                    } catch {
                        return UploadResult(success: false, error: .uploadFailed("Learning: \(learning.title)"))
                    }
                }
            }

            var results: [UploadResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Retry Logic with Exponential Backoff

    private func uploadWithRetry<T>(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Retrying a permanent failure just adds seconds of backoff to an answer
                // that will not change — a first-run "record type doesn't exist" check
                // would otherwise stall onboarding for several seconds per record type.
                guard Self.isRetryable(error) else { throw error }

                // Don't delay after the last attempt
                if attempt < maxRetries - 1 {
                    // CloudKit tells us how long to wait when it throttles; otherwise fall
                    // back to exponential backoff: 1s, 2s, 4s...
                    let delay = (error as? CKError)?.retryAfterSeconds
                        ?? baseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    /// Whether an error is worth a second attempt.
    ///
    /// Deliberately an allow-list: an unrecognised CloudKit failure is treated as permanent,
    /// so a new error code can't silently turn into a retry loop.
    private static func isRetryable(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else {
            // Non-CloudKit errors here are mostly transport hiccups from asset staging.
            return true
        }

        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .internalError:
            return true
        default:
            return false
        }
    }

    // MARK: - Individual Upload Methods
    //
    // The full `backup()` path deletes the cloud first, then creates fresh records, so a plain
    // `database.save` (default `.ifServerRecordUnchanged` policy) never hits a conflict here.
    // Both this path and the incremental `pushUpserts` path build their records through the
    // shared `makeRecord` builders below, so record shape is defined in exactly one place — and
    // both now write deterministic `CKRecord.ID`s (see `makeRecord`), which is what re-keys any
    // prior random-named backup on the first full backup (auto-sync first-enable, Task 6).

    private func uploadLearning(_ learning: Learning) async throws {
        _ = try await database.save(Self.makeRecord(CloudLearningRecord(from: learning)))
    }

    private func uploadReflection(_ reflection: Reflection) async throws {
        _ = try await database.save(Self.makeRecord(CloudReflectionRecord(from: reflection)))

        let reflectionID = reflection.id

        // Upload images
        for image in reflection.images {
            try await uploadWithRetry(maxRetries: 2) {
                try await self.uploadImageAttachment(image, reflectionID: reflectionID)
            }
        }

        // Upload voice recordings
        for voice in reflection.voiceRecordings {
            try await uploadWithRetry(maxRetries: 2) {
                try await self.uploadVoiceRecording(voice, reflectionID: reflectionID)
            }
        }

        // Upload videos. Restore replaces the local store wholesale, so anything skipped
        // here would be destroyed by the next restore rather than merely left unsynced.
        for video in reflection.videos {
            try await uploadWithRetry(maxRetries: 2) {
                try await self.uploadVideoAttachment(video, reflectionID: reflectionID)
            }
        }
    }

    private func uploadImageAttachment(_ image: ImageAttachment, reflectionID: UUID) async throws {
        _ = try await database.save(Self.makeRecord(CloudImageRecord(from: image, reflectionID: reflectionID)))
    }

    private func uploadVoiceRecording(_ voice: VoiceRecording, reflectionID: UUID) async throws {
        _ = try await database.save(Self.makeRecord(CloudVoiceRecord(from: voice, reflectionID: reflectionID)))
    }

    private func uploadVideoAttachment(_ video: VideoAttachment, reflectionID: UUID) async throws {
        _ = try await database.save(Self.makeRecord(CloudVideoRecord(from: video, reflectionID: reflectionID)))
    }

    // MARK: - Record Builders (deterministic IDs)

    /// Stages `data` as a `CKAsset` in the temporary directory. CloudKit copies the file
    /// during upload; the temp file is left for the system to reclaim (matching prior behavior).
    private static func makeAsset(_ data: Data, suffix: String) throws -> CKAsset {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + suffix)
        try data.write(to: tempURL)
        return CKAsset(fileURL: tempURL)
    }

    /// Builds a record with a deterministic `CKRecord.ID(recordName:)` == the entity's `localID`.
    /// This is what makes upserts idempotent: pushing the same entity twice overwrites in place
    /// instead of creating a duplicate. `localID` is still written as a field for the restore
    /// decode path, which matches on the field, not the recordName.
    private static func makeRecord(_ dto: CloudLearningRecord) -> CKRecord {
        let record = CKRecord(recordType: RecordType.learning, recordID: recordID(dto.id))
        record["localID"] = dto.id.uuidString
        record["title"] = dto.title
        record["descriptionText"] = dto.descriptionText
        record["colorHex"] = dto.colorHex
        record["iconName"] = dto.iconName
        record["sortOrder"] = dto.sortOrder
        record["createdAt"] = dto.createdAt
        record["updatedAt"] = dto.updatedAt
        return record
    }

    private static func makeRecord(_ dto: CloudReflectionRecord) throws -> CKRecord {
        let record = CKRecord(recordType: RecordType.reflection, recordID: recordID(dto.id))
        record["localID"] = dto.id.uuidString
        // Written even when nil (empty string) so an incremental `.changedKeys` upsert can
        // actually clear a stale link — a nil/absent key would leave the server's old value.
        // The decode reads it as a UUID, and `UUID(uuidString: "")` is nil, so "" == unlinked.
        record["learningID"] = dto.learningID?.uuidString ?? ""
        record["title"] = dto.title
        record["plainTextContent"] = dto.plainTextContent
        record["isFavorite"] = dto.isFavorite
        record["createdAt"] = dto.createdAt
        record["updatedAt"] = dto.updatedAt
        if let contentData = dto.contentData {
            record["contentData"] = try makeAsset(contentData, suffix: "")
        }
        return record
    }

    private static func makeRecord(_ dto: CloudImageRecord) throws -> CKRecord {
        let record = CKRecord(recordType: RecordType.image, recordID: recordID(dto.id))
        record["localID"] = dto.id.uuidString
        record["reflectionID"] = dto.reflectionID.uuidString
        record["caption"] = dto.caption
        record["sortOrder"] = dto.sortOrder
        record["createdAt"] = dto.createdAt
        if let imageData = dto.imageData {
            record["imageAsset"] = try makeAsset(imageData, suffix: ".jpg")
        }
        if let thumbnailData = dto.thumbnailData {
            record["thumbnailAsset"] = try makeAsset(thumbnailData, suffix: "_thumb.jpg")
        }
        return record
    }

    private static func makeRecord(_ dto: CloudVoiceRecord) throws -> CKRecord {
        let record = CKRecord(recordType: RecordType.voice, recordID: recordID(dto.id))
        record["localID"] = dto.id.uuidString
        record["reflectionID"] = dto.reflectionID.uuidString
        record["transcription"] = dto.transcription
        record["language"] = dto.language
        record["duration"] = dto.duration
        if !dto.waveformSamples.isEmpty {
            record["waveformSamples"] = dto.waveformSamples.map { NSNumber(value: $0) } as NSArray
        }
        record["sortOrder"] = dto.sortOrder
        record["createdAt"] = dto.createdAt
        if let audioData = dto.audioData {
            record["audioAsset"] = try makeAsset(audioData, suffix: ".m4a")
        }
        return record
    }

    private static func makeRecord(_ dto: CloudVideoRecord) throws -> CKRecord {
        let record = CKRecord(recordType: RecordType.video, recordID: recordID(dto.id))
        record["localID"] = dto.id.uuidString
        record["reflectionID"] = dto.reflectionID.uuidString
        record["caption"] = dto.caption
        record["duration"] = dto.duration
        record["sortOrder"] = dto.sortOrder
        record["createdAt"] = dto.createdAt
        if let videoData = dto.videoData {
            record["videoAsset"] = try makeAsset(videoData, suffix: ".mov")
        }
        if let thumbnailData = dto.thumbnailData {
            record["thumbnailAsset"] = try makeAsset(thumbnailData, suffix: "_thumb.jpg")
        }
        return record
    }

    private static func makeRecord(_ dto: CloudInsightRecord) -> CKRecord {
        let record = CKRecord(recordType: RecordType.insight, recordID: recordID(dto.id))
        record["localID"] = dto.id.uuidString
        record["text"] = dto.text
        record["typeRawValue"] = dto.typeRawValue
        record["followUp"] = dto.followUp
        record["createdAt"] = dto.createdAt
        record["updatedAt"] = dto.updatedAt
        return record
    }

    private static func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    // MARK: - Incremental Push (auto-sync)

    func pushUpserts(
        learnings: [CloudLearningRecord],
        reflections: [ReflectionUpsert]
    ) async throws {
        guard await checkCloudAvailability() == .available else {
            throw SyncError.iCloudAccountNotFound
        }

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for dto in learnings {
            recordsToSave.append(Self.makeRecord(dto))
        }

        for upsert in reflections {
            recordsToSave.append(try Self.makeRecord(upsert.reflection))
            for image in upsert.images { recordsToSave.append(try Self.makeRecord(image)) }
            for voice in upsert.voiceRecordings { recordsToSave.append(try Self.makeRecord(voice)) }
            for video in upsert.videos { recordsToSave.append(try Self.makeRecord(video)) }

            // Reconcile: drop server-side children no longer attached to this reflection.
            let stale = try await staleChildRecordIDs(
                reflectionID: upsert.reflection.id,
                keeping: upsert.currentChildIDs
            )
            recordIDsToDelete.append(contentsOf: stale)
        }

        try await modify(saving: recordsToSave, deleting: recordIDsToDelete)
    }

    func pushDeletes(_ deletions: [SyncDeletion]) async throws {
        guard await checkCloudAvailability() == .available else {
            throw SyncError.iCloudAccountNotFound
        }

        var recordIDsToDelete: [CKRecord.ID] = []
        for deletion in deletions {
            recordIDsToDelete.append(Self.recordID(deletion.entityID))
            if deletion.entityType == .reflection {
                // Also remove the reflection's attachments (matched by reflectionID, so this
                // finds them regardless of how their recordName was keyed).
                let children = try await staleChildRecordIDs(
                    reflectionID: deletion.entityID,
                    keeping: []
                )
                recordIDsToDelete.append(contentsOf: children)
            }
        }

        try await modify(saving: [], deleting: recordIDsToDelete)
    }

    /// Server-side child-record IDs for `reflectionID` whose entity UUID is not in `keep`.
    ///
    /// Identity is taken from the `localID` field (falling back to recordName) so records
    /// written before the deterministic-ID re-key are still matched correctly. A missing record
    /// type (first sync) or a not-yet-queryable `reflectionID` field degrades to "no children"
    /// rather than failing the whole push; genuine transient errors still propagate via retry.
    private func staleChildRecordIDs(
        reflectionID: UUID,
        keeping keep: Set<UUID>
    ) async throws -> [CKRecord.ID] {
        var stale: [CKRecord.ID] = []
        let childTypes = [RecordType.image, RecordType.voice, RecordType.video]
        let predicate = NSPredicate(format: "reflectionID == %@", reflectionID.uuidString)

        for type in childTypes {
            do {
                try await forEachPage(recordType: type, predicate: predicate, desiredKeys: ["localID"]) { matchResults in
                    for (recordID, result) in matchResults {
                        var childUUID: UUID?
                        if case .success(let record) = result, let raw = record["localID"] as? String {
                            childUUID = UUID(uuidString: raw)
                        }
                        if childUUID == nil {
                            childUUID = UUID(uuidString: recordID.recordName)
                        }
                        // Only delete records whose identity we could resolve and that are no
                        // longer attached; never blind-delete an unresolvable record.
                        if let childUUID, !keep.contains(childUUID) {
                            stale.append(recordID)
                        }
                    }
                }
            } catch let error as CKError where error.code == .invalidArguments {
                // `reflectionID` not marked queryable in the CloudKit schema yet — skip
                // reconciliation for this type rather than failing the sync. (Manual step:
                // set reflectionID to Queryable in the CloudKit Dashboard.)
                continue
            }
        }

        return stale
    }

    /// Batched save/delete via `modifyRecords` with a last-push-wins policy.
    ///
    /// `savePolicy: .changedKeys` overwrites freshly built records without a prior fetch;
    /// `atomically: false` is required in the default zone and lets a bad record fail in
    /// isolation. Deletes tolerate already-missing records (idempotent).
    private func modify(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID]
    ) async throws {
        let batchSize = 200

        for start in stride(from: 0, to: recordsToSave.count, by: batchSize) {
            let batch = Array(recordsToSave[start..<min(start + batchSize, recordsToSave.count)])
            try await uploadWithRetry(maxRetries: 3) {
                let (saveResults, _) = try await self.database.modifyRecords(
                    saving: batch,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
                try Self.throwFirstSaveFailure(in: saveResults)
            }
        }

        for start in stride(from: 0, to: recordIDsToDelete.count, by: batchSize) {
            let batch = Array(recordIDsToDelete[start..<min(start + batchSize, recordIDsToDelete.count)])
            try await uploadWithRetry(maxRetries: 3) {
                let (_, deleteResults) = try await self.database.modifyRecords(
                    saving: [],
                    deleting: batch,
                    savePolicy: .changedKeys,
                    atomically: false
                )
                try Self.throwFirstDeleteFailure(in: deleteResults)
            }
        }
    }

    private static func throwFirstSaveFailure(in results: [CKRecord.ID: Result<CKRecord, Error>]) throws {
        for (_, result) in results {
            if case .failure(let error) = result { throw error }
        }
    }

    private static func throwFirstDeleteFailure(in results: [CKRecord.ID: Result<Void, Error>]) throws {
        for (_, result) in results {
            if case .failure(let error) = result {
                // Deleting something already gone is success for our purposes.
                if let ckError = error as? CKError, ckError.code == .unknownItem { continue }
                throw error
            }
        }
    }
}
