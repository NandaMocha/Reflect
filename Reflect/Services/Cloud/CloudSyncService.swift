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
            let learningsCount = try await fetchRecordCount(recordType: "CKLearning")
            let reflectionsCount = try await fetchRecordCount(recordType: "CKReflection")
            let imagesCount = try await fetchRecordCount(recordType: "CKImageAttachment")
            let voiceNotesCount = try await fetchRecordCount(recordType: "CKVoiceRecording")

            let lastBackupDate = try await fetchLastBackupDate()

            syncStatusSubject.send(.idle)

            if learningsCount == 0 && reflectionsCount == 0 {
                return nil
            }

            return CloudDataSummary(
                learningsCount: learningsCount,
                reflectionsCount: reflectionsCount,
                imagesCount: imagesCount,
                voiceNotesCount: voiceNotesCount,
                lastBackupDate: lastBackupDate
            )
        } catch {
            syncStatusSubject.send(.failed(error.localizedDescription))
            throw error
        }
    }

    func backup(
        learnings: [Learning],
        reflections: [Reflection]
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
        let totalItems = learnings.count + reflections.count

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

    func restore() async throws -> SyncResult {
        syncStatusSubject.send(.syncing(progress: 0))

        let availability = await checkCloudAvailability()
        guard availability == .available else {
            throw SyncError.iCloudAccountNotFound
        }

        // This is a placeholder - actual restore would require ModelContext injection
        // to create local records from CloudKit data
        syncStatusSubject.send(.completed(Date()))

        return SyncResult(
            success: true,
            itemsSynced: 0,
            errors: [],
            completedAt: Date()
        )
    }

    func deleteAllCloudData() async throws {
        let recordTypes = ["CKLearning", "CKReflection", "CKImageAttachment", "CKVoiceRecording"]

        for recordType in recordTypes {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let results = try await database.records(matching: query)

            for (recordID, _) in results.matchResults {
                try await database.deleteRecord(withID: recordID)
            }
        }
    }

    // MARK: - Private Methods

    private func fetchRecordCount(recordType: String) async throws -> Int {
        return try await uploadWithRetry(maxRetries: 2) {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let results = try await self.database.records(matching: query)
            return results.matchResults.count
        }
    }

    private func fetchLastBackupDate() async throws -> Date? {
        return try await uploadWithRetry(maxRetries: 2) {
            let query = CKQuery(recordType: "CKLearning", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

            let results = try await self.database.records(matching: query, desiredKeys: nil, resultsLimit: 1)

            if let firstResult = results.matchResults.first,
               case .success(let record) = firstResult.1 {
                return record.modificationDate
            }

            return nil
        }
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
                // Don't delay after the last attempt
                if attempt < maxRetries - 1 {
                    // Exponential backoff: 1s, 2s, 4s...
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    // MARK: - Individual Upload Methods

    private func uploadLearning(_ learning: Learning) async throws {
        let record = CKRecord(recordType: "CKLearning")
        record["localID"] = learning.id.uuidString
        record["title"] = learning.title
        record["descriptionText"] = learning.descriptionText
        record["colorHex"] = learning.colorHex
        record["iconName"] = learning.iconName
        record["sortOrder"] = learning.sortOrder
        record["createdAt"] = learning.createdAt
        record["updatedAt"] = learning.updatedAt

        _ = try await database.save(record)
    }

    private func uploadReflection(_ reflection: Reflection) async throws {
        let record = CKRecord(recordType: "CKReflection")
        record["localID"] = reflection.id.uuidString
        record["learningID"] = reflection.learning?.id.uuidString
        record["title"] = reflection.title
        record["plainTextContent"] = reflection.plainTextContent
        record["isFavorite"] = reflection.isFavorite
        record["createdAt"] = reflection.createdAt
        record["updatedAt"] = reflection.updatedAt

        if let contentData = reflection.contentData {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try contentData.write(to: tempURL)
            record["contentData"] = CKAsset(fileURL: tempURL)
        }

        _ = try await database.save(record)

        // Upload images
        for image in reflection.images {
            try await uploadWithRetry(maxRetries: 2) {
                try await self.uploadImageAttachment(image, reflectionID: reflection.id)
            }
        }

        // Upload voice recordings
        for voice in reflection.voiceRecordings {
            try await uploadWithRetry(maxRetries: 2) {
                try await self.uploadVoiceRecording(voice, reflectionID: reflection.id)
            }
        }
    }

    private func uploadImageAttachment(_ image: ImageAttachment, reflectionID: UUID) async throws {
        let record = CKRecord(recordType: "CKImageAttachment")
        record["localID"] = image.id.uuidString
        record["reflectionID"] = reflectionID.uuidString
        record["caption"] = image.caption
        record["sortOrder"] = image.sortOrder
        record["createdAt"] = image.createdAt

        if let imageData = image.imageData {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try imageData.write(to: tempURL)
            record["imageAsset"] = CKAsset(fileURL: tempURL)
        }

        if let thumbnailData = image.thumbnailData {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_thumb.jpg")
            try thumbnailData.write(to: tempURL)
            record["thumbnailAsset"] = CKAsset(fileURL: tempURL)
        }

        _ = try await database.save(record)
    }

    private func uploadVoiceRecording(_ voice: VoiceRecording, reflectionID: UUID) async throws {
        let record = CKRecord(recordType: "CKVoiceRecording")
        record["localID"] = voice.id.uuidString
        record["reflectionID"] = reflectionID.uuidString
        record["transcription"] = voice.transcription
        record["language"] = voice.language
        record["duration"] = voice.duration
        record["sortOrder"] = voice.sortOrder
        record["createdAt"] = voice.createdAt

        if let audioData = voice.audioData {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            try audioData.write(to: tempURL)
            record["audioAsset"] = CKAsset(fileURL: tempURL)
        }

        _ = try await database.save(record)
    }
}
