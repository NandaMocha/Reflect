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
    /// The Clip guest-feedback share token, if one has been minted for this request
    /// (AC-010's `ensureRequestToken`). Nil for reflections nobody has ever shared to a
    /// guest.
    var requestToken: String? = nil
}
