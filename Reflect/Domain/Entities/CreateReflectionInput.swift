import Foundation
import UIKit

struct CreateReflectionInput {
    var title: String
    var content: String
    var learningId: UUID?
    var images: [ImageInput]
    var voiceRecordings: [VoiceRecordingInput]

    init(
        title: String = "",
        content: String = "",
        learningId: UUID? = nil,
        images: [ImageInput] = [],
        voiceRecordings: [VoiceRecordingInput] = []
    ) {
        self.title = title
        self.content = content
        self.learningId = learningId
        self.images = images
        self.voiceRecordings = voiceRecordings
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

struct VoiceRecordingInput: Identifiable {
    let id: UUID
    let existingId: UUID?
    let audioData: Data
    var transcription: String?
    let language: String
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        existingId: UUID? = nil,
        audioData: Data,
        transcription: String? = nil,
        language: String,
        duration: TimeInterval
    ) {
        self.id = id
        self.existingId = existingId
        self.audioData = audioData
        self.transcription = transcription
        self.language = language
        self.duration = duration
    }
}

struct UpdateReflectionInput {
    let reflectionId: UUID
    var title: String
    var content: String
    var learningId: UUID?
    var imagesToAdd: [ImageInput]
    var imageIdsToRemove: [UUID]
    var voiceRecordingsToAdd: [VoiceRecordingInput]
    var voiceRecordingIdsToRemove: [UUID]

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        learningId != nil
    }
}
