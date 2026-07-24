import Foundation

/// Sendable payloads that cross the actor boundary from the main-actor `SyncCoordinator`
/// into `CloudSyncService`'s background network work.
///
/// The upsert path deliberately reuses the existing `Cloud*Record` value types (see
/// `CloudBackupSnapshot.swift`) so push and restore stay symmetric — one field mapping,
/// used in both directions. `@Model` objects are never sent across the boundary; the
/// coordinator snapshots them into these structs on the main actor first.

/// A reflection plus its attachments, grouped so the push can upsert the parent and
/// reconcile its children (delete removed attachments) in one unit.
struct ReflectionUpsert: Sendable {
    let reflection: CloudReflectionRecord
    let images: [CloudImageRecord]
    let voiceRecordings: [CloudVoiceRecord]
    let videos: [CloudVideoRecord]

    /// Every attachment ID currently attached to this reflection — the set the push keeps;
    /// server-side child records outside this set are stale and get deleted.
    var currentChildIDs: Set<UUID> {
        Set(images.map(\.id)).union(voiceRecordings.map(\.id)).union(videos.map(\.id))
    }
}

/// A pending removal from the cloud, addressed by the entity's `localID` (== recordName).
struct SyncDeletion: Sendable {
    let entityType: PendingSyncOp.EntityType
    let entityID: UUID
}

// MARK: - @Model → DTO snapshots
//
// These read `@Model` properties synchronously. They are intentionally non-isolated so both
// the main-actor coordinator and the existing (off-actor) `backup()` path can build the same
// DTOs. Callers are responsible for invoking them where the model graph is safe to read —
// the coordinator does so on the main context before handing the Sendable result to the network.

extension CloudLearningRecord {
    init(from learning: Learning) {
        self.init(
            id: learning.id,
            title: learning.title,
            descriptionText: learning.descriptionText,
            colorHex: learning.colorHex,
            iconName: learning.iconName,
            sortOrder: learning.sortOrder,
            createdAt: learning.createdAt,
            updatedAt: learning.updatedAt
        )
    }
}

extension CloudReflectionRecord {
    init(from reflection: Reflection) {
        self.init(
            id: reflection.id,
            learningID: reflection.learning?.id,
            title: reflection.title,
            contentData: reflection.contentData,
            plainTextContent: reflection.plainTextContent,
            isFavorite: reflection.isFavorite,
            createdAt: reflection.createdAt,
            updatedAt: reflection.updatedAt
        )
    }
}

extension CloudImageRecord {
    init(from image: ImageAttachment, reflectionID: UUID) {
        self.init(
            id: image.id,
            reflectionID: reflectionID,
            imageData: image.imageData,
            thumbnailData: image.thumbnailData,
            caption: image.caption,
            sortOrder: image.sortOrder,
            createdAt: image.createdAt
        )
    }
}

extension CloudVoiceRecord {
    init(from voice: VoiceRecording, reflectionID: UUID) {
        self.init(
            id: voice.id,
            reflectionID: reflectionID,
            audioData: voice.audioData,
            transcription: voice.transcription,
            language: voice.language,
            duration: voice.duration,
            waveformSamples: voice.waveformSamples,
            sortOrder: voice.sortOrder,
            createdAt: voice.createdAt
        )
    }
}

extension CloudVideoRecord {
    init(from video: VideoAttachment, reflectionID: UUID) {
        self.init(
            id: video.id,
            reflectionID: reflectionID,
            videoData: video.videoData,
            thumbnailData: video.thumbnailData,
            caption: video.caption,
            duration: video.duration,
            sortOrder: video.sortOrder,
            createdAt: video.createdAt
        )
    }
}

extension ReflectionUpsert {
    init(from reflection: Reflection) {
        let id = reflection.id
        self.init(
            reflection: CloudReflectionRecord(from: reflection),
            images: reflection.images.map { CloudImageRecord(from: $0, reflectionID: id) },
            voiceRecordings: reflection.voiceRecordings.map { CloudVoiceRecord(from: $0, reflectionID: id) },
            videos: reflection.videos.map { CloudVideoRecord(from: $0, reflectionID: id) }
        )
    }
}
