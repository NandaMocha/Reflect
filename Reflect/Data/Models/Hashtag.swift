import Foundation
import SwiftData

@preconcurrency @Model
final class Hashtag {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    var reflections: [Reflection] = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name.lowercased().trimmingCharacters(in: .whitespaces)
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    var displayName: String {
        "#\(name)"
    }

    var usageCount: Int {
        reflections.count
    }
}
