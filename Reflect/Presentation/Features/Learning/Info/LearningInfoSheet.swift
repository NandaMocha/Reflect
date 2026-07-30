import SwiftUI

/// Modal showing a learning chapter's title and description, opened from the
/// info toolbar button on the reflection list. The Edit action opens the
/// existing `LearningFormView` on top; SwiftData observation keeps the
/// displayed info in sync after a save.
struct LearningInfoSheet: View {
    let learning: Learning

    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                HStack(spacing: Constants.Spacing.sm) {
                    Image(systemName: learning.iconName)
                        .font(.title3)
                        .foregroundStyle(Color(hex: learning.colorHex))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                                .fill(Color(hex: learning.colorHex).opacity(0.15))
                        )

                    Text(learning.title)
                        .font(.title3.weight(.semibold))
                }

                Group {
                    if let description = trimmedDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No description yet.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Constants.Spacing.lg)
            .navigationTitle("Chapter Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showEditForm = true
                    }
                }
            }
            .sheet(isPresented: $showEditForm) {
                LearningFormView(mode: .edit(learning))
            }
        }
        .presentationDetents([.fraction(0.3)])
    }

    private var trimmedDescription: String? {
        guard let text = learning.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}
