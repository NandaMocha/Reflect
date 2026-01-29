import Foundation
import SwiftData

@preconcurrency @Model
final class Reflection {
    @Attribute(.unique) var id: UUID
    var title: String
    @Attribute(.externalStorage) var contentData: Data?
    var plainTextContent: String
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    var learning: Learning?

    @Relationship(deleteRule: .cascade, inverse: \ImageAttachment.reflection)
    var images: [ImageAttachment] = []

    @Relationship(deleteRule: .cascade, inverse: \VoiceRecording.reflection)
    var voiceRecordings: [VoiceRecording] = []

    init(
        id: UUID = UUID(),
        title: String,
        contentData: Data? = nil,
        plainTextContent: String = "",
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        learning: Learning? = nil
    ) {
        self.id = id
        self.title = title
        self.contentData = contentData
        self.plainTextContent = plainTextContent
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.learning = learning
    }

    // MARK: - Computed Properties

    var contentPreview: String {
        let maxLength = 150
        if plainTextContent.count > maxLength {
            return String(plainTextContent.prefix(maxLength)) + "..."
        }
        return plainTextContent
    }

    var firstImage: ImageAttachment? {
        images.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    var hasImages: Bool {
        !images.isEmpty
    }

    var hasVoiceRecordings: Bool {
        !voiceRecordings.isEmpty
    }
}
