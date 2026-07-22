import Foundation
import SwiftData

@MainActor
protocol RestoreFromCloudUseCaseProtocol {
    func execute() async throws -> SyncResult
}

/// Replaces the local store with the contents of the iCloud backup.
///
/// **Replace, not merge** — this is what the Settings alert promises ("This will replace all
/// your local data…") and what `backup` assumes, since backup clears the cloud and re-uploads
/// wholesale. Anything local that is not in the backup is gone afterwards.
///
/// The split of responsibilities is deliberate: `CloudSyncService` downloads and decodes off
/// the main actor, and this use case — pinned to `@MainActor` — is the only thing that
/// touches the `ModelContext`. That is why the service takes an `apply` closure rather than a
/// context.
@MainActor
final class RestoreFromCloudUseCase: RestoreFromCloudUseCaseProtocol {
    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let cloudSyncService: CloudSyncServiceProtocol

    // MARK: - Initialization

    init(modelContext: ModelContext, cloudSyncService: CloudSyncServiceProtocol) {
        self.modelContext = modelContext
        self.cloudSyncService = cloudSyncService
    }

    // MARK: - Actions

    func execute() async throws -> SyncResult {
        let context = modelContext

        return try await cloudSyncService.restore { snapshot in
            try RestoreFromCloudUseCase.apply(snapshot, to: context)
        }
    }

    // MARK: - Private Helpers

    /// Writes a downloaded snapshot into the local store, returning the number of rows written.
    ///
    /// Everything happens in a single `save()`: a restore that failed halfway would otherwise
    /// leave the user with a store that is neither their old data nor their backup.
    private static func apply(_ snapshot: CloudBackupSnapshot, to context: ModelContext) throws -> Int {
        try wipeLocalStore(context)

        // Learnings first — reflections reference them, and the lookup tables below are how
        // the flat `learningID` / `reflectionID` fields become real SwiftData relationships.
        var learningsByID: [UUID: Learning] = [:]
        for record in snapshot.learnings {
            let learning = Learning(
                id: record.id,
                title: record.title,
                descriptionText: record.descriptionText,
                colorHex: record.colorHex,
                iconName: record.iconName,
                sortOrder: record.sortOrder,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            context.insert(learning)
            learningsByID[record.id] = learning
        }

        var reflectionsByID: [UUID: Reflection] = [:]
        for record in snapshot.reflections {
            let reflection = Reflection(
                id: record.id,
                title: record.title,
                contentData: record.contentData,
                plainTextContent: record.plainTextContent,
                isFavorite: record.isFavorite,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                // A reflection whose learning is missing from the backup is still worth
                // keeping — it lands unassigned rather than being dropped.
                learning: record.learningID.flatMap { learningsByID[$0] }
            )
            context.insert(reflection)
            reflectionsByID[record.id] = reflection
        }

        var attachmentCount = 0

        for record in snapshot.images {
            guard let reflection = reflectionsByID[record.reflectionID] else { continue }

            let image = ImageAttachment(
                id: record.id,
                imageData: record.imageData,
                thumbnailData: record.thumbnailData,
                caption: record.caption,
                sortOrder: record.sortOrder,
                createdAt: record.createdAt
            )
            image.reflection = reflection
            context.insert(image)
            attachmentCount += 1
        }

        for record in snapshot.voiceRecordings {
            guard let reflection = reflectionsByID[record.reflectionID] else { continue }

            let voice = VoiceRecording(
                id: record.id,
                audioData: record.audioData,
                transcription: record.transcription,
                language: record.language,
                duration: record.duration,
                waveformSamples: record.waveformSamples,
                sortOrder: record.sortOrder,
                createdAt: record.createdAt
            )
            voice.reflection = reflection
            context.insert(voice)
            attachmentCount += 1
        }

        for record in snapshot.videos {
            guard let reflection = reflectionsByID[record.reflectionID] else { continue }

            let video = VideoAttachment(
                id: record.id,
                videoData: record.videoData,
                thumbnailData: record.thumbnailData,
                caption: record.caption,
                duration: record.duration,
                sortOrder: record.sortOrder,
                createdAt: record.createdAt
            )
            video.reflection = reflection
            context.insert(video)
            attachmentCount += 1
        }

        try context.save()

        return learningsByID.count + reflectionsByID.count + attachmentCount
    }

    /// Clears the models a backup covers.
    ///
    /// Reflections go first so their cascade rule takes the attachments with them; the
    /// explicit attachment sweeps afterwards catch any row that was already orphaned.
    private static func wipeLocalStore(_ context: ModelContext) throws {
        try context.delete(model: Reflection.self)
        try context.delete(model: Learning.self)
        try context.delete(model: ImageAttachment.self)
        try context.delete(model: VoiceRecording.self)
        try context.delete(model: VideoAttachment.self)
    }
}
