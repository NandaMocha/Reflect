import Foundation
import SwiftData

/// A cached copy of a SpaceAnswer from CloudKit. Flattened to avoid relationships
/// and guarantee schema stability. The cache is never synced to CloudKit and always
/// rebuilds from the upstream source on refresh.
@preconcurrency @Model
final class CachedAnswer {
    // Answers are always fetched/reconciled scoped to a reflection.
    #Index<CachedAnswer>([\.reflectionID])

    @Attribute(.unique) var id: String
    var reflectionID: String
    var questionId: String
    var text: String
    @Attribute(.externalStorage) var imageData: Data?
    var authorRecordName: String?
    var authorDisplayName: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var isMine: Bool
    var lastFetchedAt: Date

    init(
        id: String,
        reflectionID: String,
        questionId: String,
        text: String,
        imageData: Data? = nil,
        authorRecordName: String? = nil,
        authorDisplayName: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        isMine: Bool,
        lastFetchedAt: Date = Date()
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.questionId = questionId
        self.text = text
        self.imageData = imageData
        self.authorRecordName = authorRecordName
        self.authorDisplayName = authorDisplayName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isMine = isMine
        self.lastFetchedAt = lastFetchedAt
    }

    /// Initialize from a domain SpaceAnswer.
    init(from domain: SpaceAnswer) {
        self.id = domain.id
        self.reflectionID = domain.reflectionID
        self.questionId = domain.questionId
        self.text = domain.text
        self.imageData = domain.imageData
        self.authorRecordName = domain.authorRecordName
        self.authorDisplayName = domain.authorDisplayName
        self.createdAt = domain.createdAt
        self.modifiedAt = domain.modifiedAt
        self.isMine = domain.isMine
        self.lastFetchedAt = Date()
    }

    /// Convert back to a domain SpaceAnswer.
    func toDomain() -> SpaceAnswer {
        SpaceAnswer(
            id: id,
            reflectionID: reflectionID,
            questionId: questionId,
            text: text,
            imageData: imageData,
            authorRecordName: authorRecordName,
            authorDisplayName: authorDisplayName,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isMine: isMine
        )
    }
}
