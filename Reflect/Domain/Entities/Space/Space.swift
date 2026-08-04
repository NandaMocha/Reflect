import Foundation

struct Space: Identifiable, Hashable, Sendable {
    let id: String            // CKRecord name
    var name: String
    var detail: String?
    var iconName: String?
    var colorHex: String?
    var isOwner: Bool
    var zoneID: SpaceZoneRef
    var createdAt: Date?
    var participantCount: Int
}
