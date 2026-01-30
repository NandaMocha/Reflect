import Foundation
import SwiftData
import UIKit

@preconcurrency @Model
final class VideoAttachment {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var videoData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var caption: String?
    var duration: TimeInterval
    var sortOrder: Int
    var createdAt: Date

    var reflection: Reflection?

    init(
        id: UUID = UUID(),
        videoData: Data? = nil,
        thumbnailData: Data? = nil,
        caption: String? = nil,
        duration: TimeInterval = 0,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.videoData = videoData
        self.thumbnailData = thumbnailData
        self.caption = caption
        self.duration = duration
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    var thumbnail: UIImage? {
        guard let thumbnailData else { return nil }
        return UIImage(data: thumbnailData)
    }

    var hasCaption: Bool {
        caption != nil && !(caption?.isEmpty ?? true)
    }
}
