import Foundation

struct SpaceAnswer: Identifiable, Hashable, Sendable {
    let id: String            // CKRecord name
    let reflectionID: String
    let questionId: String
    var text: String
    var imageData: Data?
    var authorRecordName: String?
    var authorDisplayName: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var isMine: Bool
    /// Set when this answer was authored by an unauthenticated Clip guest rather than a
    /// signed-in Space member (AC-010). Paired with `guestName` for display.
    var guestId: String? = nil
    var guestName: String? = nil

    /// True when this answer came from a Clip guest rather than a signed-in member.
    var isGuest: Bool { guestId != nil }

    static func newRecordName(reflectionID: String, questionId: String, authorRecordName: String) -> String {
        "answer-\(reflectionID)-\(questionId)-\(authorRecordName)-\(UUID().uuidString)"
    }
}
