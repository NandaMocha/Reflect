import Foundation
import SwiftData

/// A cached copy of a Space from CloudKit. Flattened to avoid relationships and
/// guarantee schema stability across CloudKit schema changes. The cache is never
/// synced to CloudKit and always rebuilds from the upstream source on refresh.
@preconcurrency @Model
final class CachedSpace {
    @Attribute(.unique) var id: String
    var name: String
    var detail: String?
    var emoji: String?
    var isOwner: Bool
    var zoneName: String
    var ownerName: String
    var laneRawValue: String
    var createdAt: Date?
    var participantCount: Int
    var lastFetchedAt: Date

    init(
        id: String,
        name: String,
        detail: String? = nil,
        emoji: String? = nil,
        isOwner: Bool,
        zoneName: String,
        ownerName: String,
        laneRawValue: String,
        createdAt: Date? = nil,
        participantCount: Int,
        lastFetchedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.emoji = emoji
        self.isOwner = isOwner
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.laneRawValue = laneRawValue
        self.createdAt = createdAt
        self.participantCount = participantCount
        self.lastFetchedAt = lastFetchedAt
    }

    /// Initialize from a domain Space, flattening the SpaceZoneRef into string fields.
    init(from domain: Space) {
        self.id = domain.id
        self.name = domain.name
        self.detail = domain.detail
        self.emoji = domain.emoji
        self.isOwner = domain.isOwner
        self.zoneName = domain.zoneID.zoneName
        self.ownerName = domain.zoneID.ownerName
        self.laneRawValue = domain.zoneID.lane == .privateDB ? "privateDB" : "sharedDB"
        self.createdAt = domain.createdAt
        self.participantCount = domain.participantCount
        self.lastFetchedAt = Date()
    }

    /// Convert back to a domain Space, reconstructing the SpaceZoneRef.
    func toDomain() -> Space {
        let lane: SpaceLane = laneRawValue == "privateDB" ? .privateDB : .sharedDB
        return Space(
            id: id,
            name: name,
            detail: detail,
            emoji: emoji,
            isOwner: isOwner,
            zoneID: SpaceZoneRef(
                zoneName: zoneName,
                ownerName: ownerName,
                lane: lane
            ),
            createdAt: createdAt,
            participantCount: participantCount
        )
    }
}
