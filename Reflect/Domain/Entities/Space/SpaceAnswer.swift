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

    static func newRecordName(reflectionID: String, questionId: String, authorRecordName: String) -> String {
        "answer-\(reflectionID)-\(questionId)-\(authorRecordName)-\(UUID().uuidString)"
    }
}
