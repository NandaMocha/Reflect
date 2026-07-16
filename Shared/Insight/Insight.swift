import Foundation
import SwiftData

/// A short, standalone thought captured to follow up on or find the answer to later.
/// Intentionally lightweight and fully independent of Reflection/Learning: no
/// relationships, no attachments, no lifecycle state.
@preconcurrency @Model
final class Insight {
    @Attribute(.unique) var id: UUID
    var text: String
    /// Backing store for `InsightType`, persisted as a raw String for schema stability.
    var typeRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        type: InsightType = .note,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.typeRawValue = type.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Typed accessor over the raw value; falls back to `.note` if unrecognised.
    var type: InsightType {
        get { InsightType(rawValue: typeRawValue) ?? .note }
        set { typeRawValue = newValue.rawValue }
    }

    /// Trimmed single-line preview for list rows.
    var preview: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
