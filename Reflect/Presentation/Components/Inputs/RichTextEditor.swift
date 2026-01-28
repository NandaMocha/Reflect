import SwiftUI

struct RichTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat

    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String = "Write your reflection here...",
        minHeight: CGFloat = 200
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty && !isFocused {
                Text(placeholder)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }

            // Text Editor
            TextEditor(text: $text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
        }
        .padding(Constants.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .stroke(isFocused ? Color.primaryDefault : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Formatting Toolbar

struct FormattingToolbar: View {
    @Binding var text: String
    var onInsertDivider: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.Spacing.xs) {
                FormatButton(icon: "bold", label: "B") {
                    insertFormatting("**", "**")
                }

                FormatButton(icon: "italic", label: "I") {
                    insertFormatting("*", "*")
                }

                FormatButton(icon: "underline", label: "U") {
                    insertFormatting("<u>", "</u>")
                }

                FormatButton(icon: "strikethrough", label: "S") {
                    insertFormatting("~~", "~~")
                }

                Divider()
                    .frame(height: 24)

                FormatButton(icon: "list.bullet", label: nil) {
                    insertPrefix("- ")
                }

                FormatButton(icon: "list.number", label: nil) {
                    insertPrefix("1. ")
                }

                FormatButton(icon: "text.quote", label: nil) {
                    insertPrefix("> ")
                }

                Divider()
                    .frame(height: 24)

                FormatButton(icon: "minus", label: nil) {
                    onInsertDivider?()
                }
            }
            .padding(.horizontal, Constants.Spacing.sm)
            .padding(.vertical, Constants.Spacing.xs)
        }
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                .fill(.ultraThinMaterial)
        )
    }

    private func insertFormatting(_ prefix: String, _ suffix: String) {
        text += "\(prefix)text\(suffix)"
        HapticManager.shared.lightImpact()
    }

    private func insertPrefix(_ prefix: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text += prefix
        } else {
            text += "\n\(prefix)"
        }
        HapticManager.shared.lightImpact()
    }
}

struct FormatButton: View {
    let icon: String
    let label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let label = label {
                    Text(label)
                        .font(.system(.body, design: .serif).weight(.bold))
                } else {
                    Image(systemName: icon)
                        .font(.body)
                }
            }
            .foregroundColor(.primary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var text = ""

    VStack {
        FormattingToolbar(text: $text)
        RichTextEditor(text: $text)
    }
    .padding()
}
