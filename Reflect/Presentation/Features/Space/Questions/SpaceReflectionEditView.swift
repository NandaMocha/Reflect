import SwiftUI

/// Post-creation edit screen for a reflection's title, note, and questions (plan Phase 5).
/// Reuses `SpaceQuestionListEditor` (TASK-017), wiring its `answerCount` closure to the
/// view model's fetched answers so a per-row caption and the destructive confirmation
/// dialog both reflect real answer counts.
struct SpaceReflectionEditView: View {
    @State var viewModel: SpaceReflectionEditViewModel
    @Environment(\.dismiss) private var dismiss
    var onSave: ((SpaceReflection) -> Void)?

    @State private var showRewordWarning = false

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                noteSection

                SpaceQuestionListEditor(
                    questions: $viewModel.questions,
                    answerCount: { viewModel.answerCount(for: $0) }
                )

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.error)
                    }
                }
            }
            .navigationTitle("Edit Reflection")
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
                        Button("Save") {
                            saveTapped()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
            .task {
                await viewModel.load()
            }
            .alert("Question Reworded", isPresented: $showRewordWarning) {
                Button("Save Anyway") {
                    Task { await save() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(rewordWarningMessage)
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $viewModel.title)
        } header: {
            Text("Title")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("Add a note...", text: $viewModel.note, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Note (Optional)")
        }
    }

    // MARK: - Actions

    private var canSave: Bool {
        !viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rewordWarningMessage: String {
        let count = viewModel.editedAnswersCount
        return "\(count) \(count == 1 ? "person" : "people") already answered with the previous wording — their answers stay linked but won't reflect your edit."
    }

    private func saveTapped() {
        if !viewModel.editedQuestionIdsWithAnswers.isEmpty {
            showRewordWarning = true
        } else {
            Task { await save() }
        }
    }

    private func save() async {
        do {
            let updated = try await viewModel.save()
            onSave?(updated)
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SpaceReflectionEditView(
        viewModel: DIContainer.shared.makeSpaceReflectionEditViewModel(
            reflection: SpaceReflection(
                id: "preview",
                spaceID: "preview",
                title: "Week 1 reflection",
                note: nil,
                questions: [
                    SpaceQuestion(id: "1", text: "What went well?", order: 0),
                    SpaceQuestion(id: "2", text: "What could be improved?", order: 1)
                ],
                imageData: nil,
                authorRecordName: nil,
                authorDisplayName: nil,
                createdAt: nil,
                modifiedAt: nil,
                isMine: true
            ),
            space: Space(
                id: "preview",
                name: "Preview Space",
                detail: nil,
                iconName: nil,
                colorHex: nil,
                isOwner: true,
                zoneID: SpaceZoneRef(zoneName: "preview", ownerName: "preview", lane: .privateDB),
                createdAt: nil,
                participantCount: 1
            )
        )
    )
}
