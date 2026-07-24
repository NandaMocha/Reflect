import Foundation

enum SpaceLane: Sendable, Hashable {
    case privateDB
    case sharedDB
}

/// Identifies which CloudKit database + zone a space lives in (owner vs joined).
struct SpaceZoneRef: Hashable, Sendable {
    let zoneName: String
    let ownerName: String
    let lane: SpaceLane
}
