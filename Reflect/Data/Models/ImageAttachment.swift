import Foundation
import SwiftData
import UIKit

@preconcurrency @Model
final class ImageAttachment {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var caption: String?
    var sortOrder: Int
    var createdAt: Date

    var reflection: Reflection?

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        caption: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    var image: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }

    var thumbnail: UIImage? {
        guard let thumbnailData else { return nil }
        return UIImage(data: thumbnailData)
    }

    var hasCaption: Bool {
        caption != nil && !(caption?.isEmpty ?? true)
    }
}
