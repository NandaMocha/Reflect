import Foundation

struct SpaceReflection: Identifiable, Hashable, Sendable {
    let id: String            // CKRecord name
    let spaceID: String
    var title: String
    var note: String?
    var questions: [SpaceQuestion]
    /// Heavily compressed JPEG attached to the request, small enough to inline.
    var imageData: Data?
    var authorRecordName: String?
    var authorDisplayName: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var isMine: Bool
}
