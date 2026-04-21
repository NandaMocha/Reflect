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
            title: "How did you feel about today? What makes you feel that way?",
            content: "How did you feel about today?\n- \n\nWhat makes you feel that way?\n- "
        ),
        (
            title: "What did you find interesting today?",
            content: "What did you find interesting today?\n- "
        ),
        (
            title: "What challenges did you face? How you handle it?",
            content: "What challenges did you face?\n- \n\nHow you handle it?\n- "
        ),
        (
            title: "What did you learn today?",
            content: "What did you learn today?\n- "
        ),
        (
            title: "What is going well and why?",
            content: "What is going well and why?\n- "
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
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }
}
