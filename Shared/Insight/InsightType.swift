import Foundation
import AppIntents

/// The kind of quick-capture insight. Categorisation only — Insight is a
/// standalone feature, decoupled from Reflection/Learning.
enum InsightType: String, Codable, CaseIterable, Identifiable, AppEnum {
    case question
    case note
    case reflection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .question: return "Question"
        case .note: return "Note"
        case .reflection: return "Reflection"
        }
    }

    var pluralTitle: String {
        switch self {
        case .question: return "Questions"
        case .note: return "Notes"
        case .reflection: return "Reflections"
        }
    }

    /// SF Symbol name.
    var icon: String {
        switch self {
        case .question: return "questionmark.circle.fill"
        case .note: return "note.text"
        case .reflection: return "quote.bubble.fill"
        }
    }

    /// Hex string WITHOUT leading '#', consumed by each target's own Color(hex:) extension.
    var colorHex: String {
        switch self {
        case .question: return "81D4FA"
        case .note: return "FFCC80"
        case .reflection: return "B39DDB"
        }
    }

    // MARK: - AppEnum
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Insight Type")
    }

    static var caseDisplayRepresentations: [InsightType: DisplayRepresentation] {
        [
            .question: DisplayRepresentation(title: "Question", image: .init(systemName: "questionmark.circle.fill")),
            .note: DisplayRepresentation(title: "Note", image: .init(systemName: "note.text")),
            .reflection: DisplayRepresentation(title: "Reflection", image: .init(systemName: "quote.bubble.fill"))
        ]
    }
}
