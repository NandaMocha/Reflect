import SwiftUI

struct ReflectionTemplateSheet: View {
    @Binding var isPresented: Bool
    let onTemplateSelected: (String) -> Void

    // Hardcoded templates
    private let templates: [(title: String, content: String)] = [
        (
            title: "What? So What? Now What?",
            content: "What happened?\n- \n\nSo, what do you feel/think?\n- \n\nNow, what do you want to do if it happens again?\n- "
        ),
        (
            title: "How did you feel about today's activity?",
            content: "How did you feel about today's activity?\n- "
        ),
        (
            title: "What did you find interesting from today's activity?",
            content: "What did you find interesting from today's activity?\n- "
        ),
        (
            title: "What challenges did you face?",
            content: "What challenges did you face?\n- "
        ),
        (
            title: "What did you learn from today's activity?",
            content: "What did you learn from today's activity?\n- "
        )
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(templates.indices, id: \.self) { index in
                    Button {
                        onTemplateSelected(templates[index].content)
                        isPresented = false
                        HapticManager.shared.lightImpact()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(templates[index].title)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Reflection Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
