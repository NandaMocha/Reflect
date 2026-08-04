import Foundation
import SwiftData

/// A cached copy of a SpaceReflection from CloudKit. Flattened to avoid relationships
/// and guarantee schema stability. The cache is never synced to CloudKit and always
/// rebuilds from the upstream source on refresh.
@preconcurrency @Model
final class CachedSpaceReflection {
    // Reflections are always fetched/reconciled scoped to a space.
    #Index<CachedSpaceReflection>([\.spaceID])

    @Attribute(.unique) var id: String
    var spaceID: String
    var title: String
    var note: String?
    var questionsData: Data
    @Attribute(.externalStorage) var imageData: Data?
    var authorRecordName: String?
    var authorDisplayName: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var isMine: Bool
    var lastFetchedAt: Date

    init(
        id: String,
        spaceID: String,
        title: String,
        note: String? = nil,
        questionsData: Data = Data(),
        imageData: Data? = nil,
        authorRecordName: String? = nil,
        authorDisplayName: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        isMine: Bool,
        lastFetchedAt: Date = Date()
    ) {
        self.id = id
        self.spaceID = spaceID
        self.title = title
        self.note = note
        self.questionsData = questionsData
        self.imageData = imageData
        self.authorRecordName = authorRecordName
        self.authorDisplayName = authorDisplayName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isMine = isMine
        self.lastFetchedAt = lastFetchedAt
    }

    /// Initialize from a domain SpaceReflection.
    init(from domain: SpaceReflection) {
        self.id = domain.id
        self.spaceID = domain.spaceID
        self.title = domain.title
        self.note = domain.note
        self.questionsData = (try? JSONEncoder().encode(domain.questions)) ?? Data()
        self.imageData = domain.imageData
        self.authorRecordName = domain.authorRecordName
        self.authorDisplayName = domain.authorDisplayName
        self.createdAt = domain.createdAt
        self.modifiedAt = domain.modifiedAt
        self.isMine = domain.isMine
        self.lastFetchedAt = Date()
    }

    /// Convert back to a domain SpaceReflection.
    func toDomain() -> SpaceReflection {
        let questions = (try? JSONDecoder().decode([SpaceQuestion].self, from: questionsData)) ?? []
        return SpaceReflection(
            id: id,
            spaceID: spaceID,
            title: title,
            note: note,
            questions: questions,
            imageData: imageData,
            authorRecordName: authorRecordName,
            authorDisplayName: authorDisplayName,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isMine: isMine
        )
    }
}
