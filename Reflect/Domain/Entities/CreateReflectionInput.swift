import Foundation
import UIKit
import SwiftData

struct CreateReflectionInput {
    var title: String
    var content: String
    var learningId: UUID?
    var promptID: String?
    var images: [ImageInput]
    var videos: [VideoInput]
    var voiceRecordings: [VoiceRecordingInput]
    var createdAt: Date
    var capturedLocation: CapturedLocation?
    var modelContext: ModelContext?

    init(
        title: String = "",
        content: String = "",
        learningId: UUID? = nil,
        promptID: String? = nil,
        images: [ImageInput] = [],
        videos: [VideoInput] = [],
        voiceRecordings: [VoiceRecordingInput] = [],
        createdAt: Date = Date(),
        capturedLocation: CapturedLocation? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.title = title
        self.content = content
        self.learningId = learningId
        self.promptID = promptID
        self.images = images
        self.videos = videos
        self.voiceRecordings = voiceRecordings
        self.createdAt = createdAt
        self.capturedLocation = capturedLocation
        self.modelContext = modelContext
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        learningId != nil
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Title is required")
        }
        if title.count > Constants.Limits.reflectionTitleMaxLength {
            errors.append("Title is too long")
        }
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Content is required")
        }
        if learningId == nil {
            errors.append("Please select a learning")
        }
        if images.count > Constants.Limits.maxImagesPerReflection {
            errors.append("Too many images")
        }
        if voiceRecordings.count > Constants.Limits.maxVoiceNotesPerReflection {
            errors.append("Too many voice recordings")
        }
        return errors
    }
}

struct ImageInput: Identifiable {
    let id: UUID
    let image: UIImage
    var caption: String?

    init(id: UUID = UUID(), image: UIImage, caption: String? = nil) {
        self.id = id
        self.image = image
        self.caption = caption
    }
}

struct VideoInput: Identifiable {
    let id: UUID
    let videoData: Data
    let thumbnailImage: UIImage
    let duration: TimeInterval
    var caption: String?

    init(id: UUID = UUID(), videoData: Data, thumbnailImage: UIImage, duration: TimeInterval, caption: String? = nil) {
        self.id = id
        self.videoData = videoData
        self.thumbnailImage = thumbnailImage
        self.duration = duration
        self.caption = caption
    }
}

struct VoiceRecordingInput: Identifiable {
    let id: UUID
    let existingId: UUID?
    let audioData: Data
    var transcription: String?
    let language: String
    let duration: TimeInterval
    let waveformSamples: [Float]
    let fromWidget: Bool  // Track if recording originated from widget

    init(
        id: UUID = UUID(),
        existingId: UUID? = nil,
        audioData: Data,
        transcription: String? = nil,
        language: String,
        duration: TimeInterval,
        waveformSamples: [Float] = [],
        fromWidget: Bool = false
    ) {
        self.id = id
        self.existingId = existingId
        self.audioData = audioData
        self.transcription = transcription
        self.language = language
        self.duration = duration
        self.waveformSamples = waveformSamples
        self.fromWidget = fromWidget
    }
}

struct UpdateReflectionInput {
    let reflectionId: UUID
    var title: String
    var content: String
    var learningId: UUID?
    var createdAt: Date
    var capturedLocation: CapturedLocation?
    /// All images the user wants on the saved reflection after this update. The use case diffs
    /// against the current SwiftData state to decide what to add, keep, or remove.
    var images: [ImageInput]
    /// IDs among `images` that already exist in the database (so the use case treats them as
    /// updates-in-place rather than new attachments to compress).
    var existingImageIds: Set<UUID>
    var videos: [VideoInput]
    var existingVideoIds: Set<UUID>
    var voiceRecordings: [VoiceRecordingInput]
    var modelContext: ModelContext?

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        learningId != nil
    }
}

struct CapturedLocation {
    let latitude: Double
    let longitude: Double
    let name: String?
}
