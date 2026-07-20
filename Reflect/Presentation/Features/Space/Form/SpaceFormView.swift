import SwiftUI
import CloudKit

/// Sheet for creating a new space. On successful create it presents the CloudKit sharing
/// controller (`CloudSharingView`) so the owner can invite members without an extra step.
struct SpaceFormView: View {
    @State private var viewModel = DIContainer.shared.makeSpaceFormViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var showShareSheet = false

    /// Must match the entitlement / `SpaceCloudService`'s container identifier.
    private let spaceContainer = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")

    private var isOverLimit: Bool {
        viewModel.characterCount > viewModel.characterLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Space name", text: $viewModel.name)
                        .focused($nameFocused)
                } footer: {
                    HStack {
                        Text("Everyone you invite can read and give feedback.")
                        Spacer()
                        Text("\(viewModel.characterCount)/\(viewModel.characterLimit)")
                            .foregroundStyle(isOverLimit ? Color.error : .secondary)
                            .monospacedDigit()
                    }
                }

                Section("Optional") {
                    TextField("Emoji", text: $viewModel.emoji)
                        .onChange(of: viewModel.emoji) { _, newValue in
                            // Keep it to a single emoji glyph.
                            if let first = newValue.first {
                                viewModel.emoji = String(first)
                            } else {
                                viewModel.emoji = ""
                            }
                        }
                    TextField("Description", text: $viewModel.detail, axis: .vertical)
                        .lineLimit(1...4)
                }

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
}

#Preview {
    SpaceFormView()
}
