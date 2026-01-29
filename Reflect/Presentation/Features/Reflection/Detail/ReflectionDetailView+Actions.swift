import SwiftUI
import SwiftData

// MARK: - Actions Extension

extension ReflectionDetailView {
    var shareText: String {
        var text = "# \(reflection.title)\n\n"
        text += reflection.plainTextContent

        if !reflection.hashtags.isEmpty {
            text += "\n\n"
            text += reflection.hashtags.map { $0.displayName }.joined(separator: " ")
        }

        return text
    }

    func copyText() {
        UIPasteboard.general.string = shareText
        HapticManager.shared.success()
    }

    func deleteReflection() {
        modelContext.delete(reflection)
        try? modelContext.save()
        HapticManager.shared.success()
        dismiss()
    }
}
