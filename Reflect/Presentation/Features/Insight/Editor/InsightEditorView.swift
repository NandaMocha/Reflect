import SwiftUI

struct InsightEditorView: View {
    @State private var viewModel: InsightEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    init(mode: InsightEditorViewModel.Mode = .create) {
        self._viewModel = State(initialValue: DIContainer.shared.makeInsightEditorViewModel(mode: mode))
    }

    private var navigationTitle: String {
        viewModel.isEditing ? "Edit Insight" : "New Insight"
    }

    private var isOverLimit: Bool {
        viewModel.characterCount > viewModel.characterLimit
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    typePicker

                    textEditor

                    characterCounter

                    followUpField

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.error)
                    }
                }
                .padding(Constants.Spacing.md)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.save() {
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.canSave)
                    }
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }

    // MARK: - Subviews

    private var typePicker: some View {
        HStack(spacing: Constants.Spacing.sm) {
            ForEach(InsightType.allCases) { type in
                typeChip(for: type)
            }
        }
    }

    private func typeChip(for type: InsightType) -> some View {
        let isSelected = viewModel.type == type
        let tintColor = Color(hex: type.colorHex)

        return Button {
            HapticManager.shared.selection()
            viewModel.type = type
        } label: {
            Label(type.title, systemImage: type.icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, Constants.Spacing.sm)
                .padding(.vertical, Constants.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                        .fill(isSelected ? tintColor.opacity(0.2) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                        .strokeBorder(isSelected ? tintColor : .clear, lineWidth: 1.5)
                )
                .foregroundStyle(isSelected ? tintColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var textEditor: some View {
        TextEditor(text: $viewModel.text)
            .focused($isTextFieldFocused)
            .font(.body)
            .frame(height: 200)
            .scrollContentBackground(.hidden)
            .padding(Constants.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(Color.secondary.opacity(0.08))
            )
    }

    private var characterCounter: some View {
        HStack {
            Spacer()
            Text("\(viewModel.characterCount)/\(viewModel.characterLimit)")
                .font(.caption)
                .foregroundStyle(isOverLimit ? Color.error : Color.secondary)
        }
    }

    private var followUpField: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Label("Follow-up", systemImage: "arrowshape.turn.up.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.followUp)
                .font(.body)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(Constants.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.followUp.isEmpty {
                        Text("Add the answer or next step when you revisit this…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Constants.Spacing.sm + 5)
                            .padding(.vertical, Constants.Spacing.sm + 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

#Preview("Create") {
    InsightEditorView(mode: .create)
}
