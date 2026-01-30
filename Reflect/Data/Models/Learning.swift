import Foundation
import SwiftData

@preconcurrency @Model
final class Learning {
    @Attribute(.unique) var id: UUID
    var title: String
    var descriptionText: String?
    var colorHex: String
    var iconName: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Reflection.learning)
    var reflections: [Reflection] = []

    init(
        id: UUID = UUID(),
        title: String,
        descriptionText: String? = nil,
        colorHex: String = "3AAFA9",
        iconName: String = "book.fill",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var reflectionCount: Int {
        reflections.count
    }
}
