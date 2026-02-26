import SwiftUI
import SwiftData

// MARK: - Actions Extension

extension ReflectionDetailView {
    var shareText: String {
        var text = "# \(reflection.title)\n\n"
        text += reflection.plainTextContent
        return text
    }

    var shareItems: [Any] {
        var items: [Any] = [shareText]

        // Add images if available
        for imageAttachment in reflection.images.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if let image = imageAttachment.image {
                items.append(image)
            }
        }

        return items
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
