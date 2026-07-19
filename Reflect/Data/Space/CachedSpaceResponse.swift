import Foundation
import SwiftData

/// A cached copy of a SpaceResponse from CloudKit. Flattened to avoid relationships
/// and guarantee schema stability. The cache is never synced to CloudKit and always
/// rebuilds from the upstream source on refresh.
@preconcurrency @Model
final class CachedSpaceResponse {
    // Responses are always fetched/reconciled scoped to a reflection.
    #Index<CachedSpaceResponse>([\.reflectionID])

    @Attribute(.unique) var id: String
    var reflectionID: String
    var body: String
    var authorRecordName: String?
    var authorDisplayName: String?
    var createdAt: Date?
    var isMine: Bool
    var lastFetchedAt: Date

    init(
        id: String,
        reflectionID: String,
        body: String,
        authorRecordName: String? = nil,
        authorDisplayName: String? = nil,
        createdAt: Date? = nil,
        isMine: Bool,
        lastFetchedAt: Date = Date()
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.body = body
        self.authorRecordName = authorRecordName
        self.authorDisplayName = authorDisplayName
        self.createdAt = createdAt
        self.isMine = isMine
        self.lastFetchedAt = lastFetchedAt
    }

    /// Initialize from a domain SpaceResponse.
    init(from domain: SpaceResponse) {
        self.id = domain.id
        self.reflectionID = domain.reflectionID
        self.body = domain.body
        self.authorRecordName = domain.authorRecordName
        self.authorDisplayName = domain.authorDisplayName
        self.createdAt = domain.createdAt
        self.isMine = domain.isMine
        self.lastFetchedAt = Date()
    }

    /// Convert back to a domain SpaceResponse.
    func toDomain() -> SpaceResponse {
        SpaceResponse(
            id: id,
            reflectionID: reflectionID,
            body: body,
            authorRecordName: authorRecordName,
            authorDisplayName: authorDisplayName,
            createdAt: createdAt,
            isMine: isMine
        )
    }
}
