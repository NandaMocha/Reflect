import SwiftUI

/// Reusable medium-detent sheet for picking a single Learning from a list. Callback-based —
/// the caller decides what to do with the selection; the sheet dismisses itself via
/// `@Environment(\.dismiss)` after the callback runs.
struct LearningPickerSheet: View {
    let title: String
    let learnings: [Learning]
    let currentSelection: Learning?
    let onSelect: (Learning) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        title: String = "Select Learning",
        learnings: [Learning],
        currentSelection: Learning? = nil,
        onSelect: @escaping (Learning) -> Void
    ) {
        self.title = title
        self.learnings = learnings
        self.currentSelection = currentSelection
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(learnings) { learning in
                    Button {
                        onSelect(learning)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: learning.iconName)
                                .foregroundColor(Color(hex: learning.colorHex))
                            Text(learning.title)
                                .foregroundColor(.primary)
                            Spacer()
                            if currentSelection?.id == learning.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.primaryDefault)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
