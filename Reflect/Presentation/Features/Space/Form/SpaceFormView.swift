import SwiftUI
import CloudKit

/// Sheet for creating a new space. On successful create it presents the CloudKit sharing
/// controller (`CloudSharingView`) so the owner can invite members without an extra step.
///
/// The layout deliberately mirrors `LearningFormView` — name, a grid-based icon picker, an
/// optional description, and a live preview — so creating a space feels the same as creating
/// a learning. Spaces store an emoji (not an SF Symbol + color), so the icon picker is an
/// emoji grid with a free-entry field for anything outside the curated set.
struct SpaceFormView: View {
    @State private var viewModel = DIContainer.shared.makeSpaceFormViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var showShareSheet = false

    /// Must match the entitlement / `SpaceCloudService`'s container identifier.
    private let spaceContainer = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")

    /// Curated emoji, mirroring the 20-icon grid in `LearningFormView`.
    private let availableEmojis = [
        "📚", "💡", "🎯", "🔬", "🎨",
        "🎮", "🌍", "❤️", "⭐️", "⚡️",
        "🌱", "🎓", "🧠", "🛠️", "📈",
        "🏆", "🔥", "✏️", "🗂️", "✈️"
    ]

    private var isOverLimit: Bool {
        viewModel.characterCount > viewModel.characterLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                iconSection
                descriptionSection
                previewSection

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.error)
                    }
                }
            }
            .navigationTitle("New Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task {
                                if await viewModel.save() != nil {
                                    showShareSheet = true
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.canSave)
                    }
                }
            }
            .onAppear { nameFocused = true }
            // The share sheet's own dismissal is delegate-driven; when it goes away
            // (saved or stopped) we close the whole form back to the list.
            .sheet(isPresented: $showShareSheet, onDismiss: { dismiss() }) {
                if let share = viewModel.createdShare {
                    CloudSharingView(
                        share: share,
                        container: spaceContainer,
                        spaceName: viewModel.createdSpace?.name ?? viewModel.name,
                        onSaved: { showShareSheet = false },
                        onStopped: { showShareSheet = false },
                        onError: { _ in showShareSheet = false }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Space name", text: $viewModel.name)
                .focused($nameFocused)
        } header: {
            Text("Name")
        } footer: {
            HStack {
                Text("Everyone you invite can read and give feedback.")
                Spacer()
                Text("\(viewModel.characterCount)/\(viewModel.characterLimit)")
                    .foregroundStyle(isOverLimit ? Color.error : .secondary)
                    .monospacedDigit()
            }
        }
    }

    private var iconSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(availableEmojis, id: \.self) { emoji in
                    emojiButton(for: emoji)
                }
            }
            .padding(.vertical, 8)

            // Keep the ability to pick any emoji, not just the curated grid above. Both this
            // field and the grid write the same `emoji` value, so they stay in sync.
            TextField("Or type your own emoji", text: $viewModel.emoji)
                .onChange(of: viewModel.emoji) { _, newValue in
                    // Keep it to a single emoji glyph.
                    if let first = newValue.first {
                        viewModel.emoji = String(first)
                    } else {
                        viewModel.emoji = ""
                    }
                }
        } header: {
            Text("Icon (Optional)")
        }
    }

    private func emojiButton(for emoji: String) -> some View {
        let isSelected = viewModel.emoji == emoji
        return Button {
            HapticManager.shared.selection()
            viewModel.emoji = emoji
        } label: {
            Text(emoji)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.primaryDefault.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primaryDefault, lineWidth: isSelected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private var descriptionSection: some View {
        Section {
            TextField("Describe what this space is about...", text: $viewModel.detail, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Description (Optional)")
        }
    }

    private var previewSection: some View {
        Section {
            SpaceRowView(space: previewSpace)
        } header: {
            Text("Preview")
        }
    }

    // MARK: - Preview Model

    /// A throwaway `Space` built from the current form values, used only to render the
    /// preview row (mirrors the `LearningCard` preview in the learning form).
    private var previewSpace: Space {
        let trimmedName = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = viewModel.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return Space(
            id: "preview",
            name: trimmedName.isEmpty ? "Space name" : trimmedName,
            detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
            emoji: viewModel.emoji.isEmpty ? nil : viewModel.emoji,
            isOwner: true,
            zoneID: SpaceZoneRef(zoneName: "preview", ownerName: "preview", lane: .privateDB),
            createdAt: nil,
            participantCount: 1
        )
    }
}

#Preview {
    SpaceFormView()
}
