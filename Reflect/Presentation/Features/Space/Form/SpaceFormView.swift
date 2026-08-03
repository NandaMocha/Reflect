import SwiftUI
import CloudKit

/// Sheet for creating a new space. On successful create it presents the CloudKit sharing
/// controller (`CloudSharingView`) so the owner can invite members without an extra step.
///
/// The layout deliberately mirrors `LearningFormView` — name, an optional description, an
/// SF Symbol icon grid, a color grid, and a live preview — so creating a space feels the
/// same as creating a learning. An icon and color are always selected (defaulted on
/// appear), so a space can never end up with no icon.
struct SpaceFormView: View {
    @State private var viewModel = DIContainer.shared.makeSpaceFormViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var showShareSheet = false

    /// Must match the entitlement / `SpaceCloudService`'s container identifier.
    private let spaceContainer = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")

    /// Same 20-icon grid as `LearningFormView`, so the two pickers read as the same set
    /// of choices.
    private let availableIcons = [
        "book.fill", "lightbulb.fill", "laptopcomputer", "paintbrush.fill",
        "music.note", "gamecontroller.fill", "globe", "heart.fill",
        "star.fill", "bolt.fill", "leaf.fill", "graduationcap.fill",
        "brain.head.profile", "hammer.fill", "wrench.fill", "chart.line.uptrend.xyaxis",
        "person.fill", "flag.fill", "target", "airplane"
    ]

    private var isOverLimit: Bool {
        viewModel.characterCount > viewModel.characterLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                descriptionSection
                iconSection
                colorSection
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
            .onAppear {
                nameFocused = true
                // Default to a selected icon/color so a space always has one — the grids
                // are never in a "nothing selected" state.
                if viewModel.iconName.isEmpty {
                    viewModel.iconName = availableIcons.first ?? "book.fill"
                }
                if viewModel.colorHex.isEmpty {
                    viewModel.colorHex = Constants.LearningColors.all.first ?? Constants.LearningColors.coral
                }
            }
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
        let isSelected = viewModel.iconName == icon
        let selectedColor = viewModel.colorHex.isEmpty ? Constants.LearningColors.all[0] : viewModel.colorHex
        return Button {
            HapticManager.shared.selection()
            viewModel.iconName = icon
        } label: {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color(hex: selectedColor) : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    private var colorSection: some View {
        Section {
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
        let isSelected = viewModel.colorHex == colorHex
        return Button {
            HapticManager.shared.selection()
            viewModel.colorHex = colorHex
        } label: {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                    }
                }
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
            iconName: viewModel.iconName.isEmpty ? nil : viewModel.iconName,
            colorHex: viewModel.colorHex.isEmpty ? nil : viewModel.colorHex,
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
