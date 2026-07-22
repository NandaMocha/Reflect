import SwiftUI
import SwiftData

struct LearningFormView: View {
    enum Mode: Equatable {
        case create
        case edit(Learning)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create):
                return true
            case let (.edit(l1), .edit(l2)):
                return l1.id == l2.id
            default:
                return false
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedIcon: String = "book.fill"
    @State private var selectedColor: String = Constants.LearningColors.all[0]
    @State private var showDiscardAlert = false
    @State private var hasChanges = false

    private let availableIcons = [
        "book.fill", "lightbulb.fill", "laptopcomputer", "paintbrush.fill",
        "music.note", "gamecontroller.fill", "globe", "heart.fill",
        "star.fill", "bolt.fill", "leaf.fill", "graduationcap.fill",
        "brain.head.profile", "hammer.fill", "wrench.fill", "chart.line.uptrend.xyaxis",
        "person.fill", "flag.fill", "target", "airplane"
    ]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navigationTitle: String {
        isEditing ? "Edit Learning" : "New Learning"
    }

    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        // Match the "too long" footer warning so Save can't submit an over-limit title.
        return !trimmed.isEmpty && title.count <= Constants.Limits.learningTitleMaxLength
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                descriptionSection
                iconSection
                colorSection
                previewSection
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .onAppear {
                loadExistingData()
            }
            .onChange(of: title) { _, _ in hasChanges = true }
            .onChange(of: descriptionText) { _, _ in hasChanges = true }
            .onChange(of: selectedIcon) { _, _ in hasChanges = true }
            .onChange(of: selectedColor) { _, _ in hasChanges = true }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Enter learning title...", text: $title)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Title")
        } footer: {
            if title.count > Constants.Limits.learningTitleMaxLength {
                Text("Title is too long (\(title.count)/\(Constants.Limits.learningTitleMaxLength))")
                    .foregroundStyle(Color.error)
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField("Describe what you're learning...", text: $descriptionText, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Description (Optional)")
        }
    }

    private var iconSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(availableIcons, id: \.self) { icon in
                    iconButton(for: icon)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Icon")
        }
    }

    private func iconButton(for icon: String) -> some View {
        Button {
            HapticManager.shared.selection()
            selectedIcon = icon
        } label: {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(selectedIcon == icon ? .white : .primary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedIcon == icon ? Color(hex: selectedColor) : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    private var colorSection: some View {
        Section {
            // A grid (not a fixed HStack) so the swatches distribute across the row and wrap on
            // narrow devices instead of overflowing/clipping the trailing colors.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 40), spacing: Constants.Spacing.sm)],
                spacing: Constants.Spacing.sm
            ) {
                ForEach(Constants.LearningColors.all, id: \.self) { colorHex in
                    colorButton(for: colorHex)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Color")
        }
    }

    private func colorButton(for colorHex: String) -> some View {
        let isSelected = selectedColor == colorHex
        return Button {
            HapticManager.shared.selection()
            selectedColor = colorHex
        } label: {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            // Legible even on the lighter swatches.
                            .shadow(color: .black.opacity(0.35), radius: 1)
                    }
                }
                // A halo ring makes the selection obvious regardless of swatch color.
                .overlay {
                    Circle()
                        .stroke(Color.primary, lineWidth: 2)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var previewSection: some View {
        Section {
            LearningCard(
                learning: Learning(
                    title: title.isEmpty ? "Learning Title" : title,
                    descriptionText: descriptionText,
                    colorHex: selectedColor,
                    iconName: selectedIcon
                )
            ) {}
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Preview")
        }
    }

    // MARK: - Methods

    private func loadExistingData() {
        if case .edit(let learning) = mode {
            title = learning.title
            descriptionText = learning.descriptionText ?? ""
            selectedIcon = learning.iconName
            selectedColor = learning.colorHex
            hasChanges = false
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        switch mode {
        case .create:
            let learning = Learning(
                title: trimmedTitle,
                descriptionText: descriptionText.isEmpty ? nil : descriptionText,
                colorHex: selectedColor,
                iconName: selectedIcon
            )
            modelContext.insert(learning)

        case .edit(let learning):
            learning.title = trimmedTitle
            learning.descriptionText = descriptionText.isEmpty ? nil : descriptionText
            learning.colorHex = selectedColor
            learning.iconName = selectedIcon
            learning.updatedAt = Date()
        }

        do {
            try modelContext.save()
            HapticManager.shared.success()
            dismiss()
        } catch {
            HapticManager.shared.error()
        }
    }
}

#Preview("Create") {
    LearningFormView(mode: .create)
        .modelContainer(for: Learning.self, inMemory: true)
}
