import Foundation

struct SpaceResponse: Identifiable, Hashable, Sendable {
    let id: String            // CKRecord name
    let reflectionID: String
    var body: String
    var authorRecordName: String?
    var authorDisplayName: String?
    var createdAt: Date?
    var isMine: Bool
}
