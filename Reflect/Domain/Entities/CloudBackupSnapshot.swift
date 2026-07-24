import Foundation

/// A decoded, in-memory copy of everything `CloudSyncService.backup(learnings:reflections:)`
/// wrote to the private CloudKit database.
///
/// These are plain value types on purpose. CloudKit fetching happens off the main actor,
/// while the SwiftData write has to happen *on* it — so the download stage produces a
/// `Sendable` snapshot and hands it across the actor boundary, rather than trying to move
/// `CKRecord`s or a `ModelContext` around.
///
/// Relationships are carried as flat IDs (`learningID`, `reflectionID`) and re-linked when
/// the snapshot is applied. See `RestoreFromCloudUseCase`.
struct CloudBackupSnapshot: Sendable {
    var learnings: [CloudLearningRecord] = []
    var reflections: [CloudReflectionRecord] = []
    var images: [CloudImageRecord] = []
    var voiceRecordings: [CloudVoiceRecord] = []
    var videos: [CloudVideoRecord] = []

    /// Rows that will actually be written locally. Attachments whose parent reflection is
    /// missing get dropped at apply time, so this is an upper bound, not a promise.
    var totalItems: Int {
        learnings.count + reflections.count + images.count + voiceRecordings.count + videos.count
    }

    var isEmpty: Bool { totalItems == 0 }
}

struct CloudLearningRecord: Sendable {
    let id: UUID
    let title: String
    let descriptionText: String?
    let colorHex: String
    let iconName: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
}

struct CloudReflectionRecord: Sendable {
    let id: UUID
    /// `nil` when the reflection was backed up without a learning attached.
    let learningID: UUID?
    let title: String
    let contentData: Data?
    let plainTextContent: String
    let isFavorite: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct CloudImageRecord: Sendable {
    let id: UUID
    let reflectionID: UUID
    let imageData: Data?
    let thumbnailData: Data?
    let caption: String?
    let sortOrder: Int
    let createdAt: Date
}

struct CloudVoiceRecord: Sendable {
    let id: UUID
    let reflectionID: UUID
    let audioData: Data?
    let transcription: String?
    let language: String
    let duration: TimeInterval
    let waveformSamples: [Float]
    let sortOrder: Int
    let createdAt: Date
}

struct CloudVideoRecord: Sendable {
    let id: UUID
    let reflectionID: UUID
    let videoData: Data?
    let thumbnailData: Data?
    let caption: String?
    let duration: TimeInterval
    let sortOrder: Int
    let createdAt: Date
}
