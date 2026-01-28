import SwiftUI

struct LearningPickerSheet: View {
    @Binding var selectedLearning: Learning?
    let learnings: [Learning]
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(learnings) { learning in
                    Button {
                        selectedLearning = learning
                        onDismiss()
                    } label: {
                        HStack {
                            Image(systemName: learning.iconName)
                                .foregroundColor(Color(hex: learning.colorHex))
                            Text(learning.title)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedLearning?.id == learning.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.primaryDefault)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Learning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
