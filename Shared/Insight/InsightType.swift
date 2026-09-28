import Foundation
import AppIntents
import SwiftUI

/// The kind of quick-capture insight. Categorisation only — Insight is a
/// standalone feature, decoupled from Reflection/Learning.
///
/// Note: there is deliberately no `reflection` case — a full Reflection is its own
/// feature, so a "reflection" insight type would be redundant.
enum InsightType: String, Codable, CaseIterable, Identifiable, AppEnum {
    case question
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .question: return "Question"
        case .note: return "Note"
        }
    }

    var pluralTitle: String {
        switch self {
        case .question: return "Questions"
        case .note: return "Notes"
        }
    }

    /// SF Symbol name.
    var icon: String {
        switch self {
        case .question: return "questionmark.circle.fill"
        case .note: return "note.text"
        }
    }

    /// Hex string WITHOUT leading '#', consumed by each target's own Color(hex:) extension.
    /// Light and dark differ because the tag pill tints its fill with the same colour as its
    /// text, so no single hex reaches WCAG AA 4.5:1 in both appearances
    /// (see `InsightTypeContrastTests`).
    func colorHex(for colorScheme: ColorScheme) -> String {
        switch (self, colorScheme) {
        case (.question, .dark): return "C7EBFF"
        case (.question, _): return "065F8F"
        case (.note, .dark): return "FFE0BD"
        case (.note, _): return "854806"
        }
    }

    // MARK: - AppEnum
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Insight Type")
    }

    static var caseDisplayRepresentations: [InsightType: DisplayRepresentation] {
        [
            .question: DisplayRepresentation(title: "Question", image: .init(systemName: "questionmark.circle.fill")),
            .note: DisplayRepresentation(title: "Note", image: .init(systemName: "note.text"))
        ]
    }
}
