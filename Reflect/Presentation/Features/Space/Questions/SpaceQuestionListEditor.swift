import SwiftUI

/// Reusable editor for a feedback request's question list. Binds directly to an
/// `[SpaceQuestion]` array so both the create-space compose sheet (Phase 2) and the
/// post-creation "Edit questions" screen (Phase 5) can share one implementation.
///
/// Each row is a multiline `TextField` with a character counter, a delete button, and
/// drag-to-reorder (long-press, no `EditButton` required — SwiftUI's `List` supports this
/// natively once `.onMove` is attached). Reordering and deletion both rewrite `order` so it
/// always matches the array index.
///
/// `answerCount` lets a caller (the Phase 5 edit screen) surface how many answers already
/// exist for a question; when a row with answers is deleted, a destructive
/// `confirmationDialog` gates the removal instead of deleting immediately. Callers with no
/// answers yet (the create-space compose flow) can leave it at the default, which deletes
/// rows immediately as before.
struct SpaceQuestionListEditor: View {
    @Binding var questions: [SpaceQuestion]
    var answerCount: (String) -> Int = { _ in 0 }

    @State private var pendingDeleteQuestion: SpaceQuestion?

    private var isAtLimit: Bool {
        questions.count >= Constants.Limits.spaceMaxQuestions
    }

    var body: some View {
        Section {
            // Iterates values (not `ForEach($questions)`) so a row never holds an
            // index-based binding into the array. A row that deletes itself used to leave
            // SwiftUI re-evaluating that stale binding, which trapped with "Index out of
            // range"; `binding(for:)` below resolves by id and no-ops once the row is gone.
            ForEach(questions) { question in
                questionRow(question: question)
            }
            .onDelete(perform: delete)
            .onMove(perform: move)

            addQuestionButton
        } header: {
            Text("Questions")
        } footer: {
            Text("\(questions.count) of \(Constants.Limits.spaceMaxQuestions)")
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { pendingDeleteQuestion != nil },
                set: { isPresented in if !isPresented { pendingDeleteQuestion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Question", role: .destructive) {
                if let question = pendingDeleteQuestion {
                    performDelete(id: question.id)
                }
                pendingDeleteQuestion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteQuestion = nil
            }
        } message: {
            Text("Members' answers to it will be permanently deleted.")
        }
    }

    private var deleteConfirmationTitle: String {
        let count = pendingDeleteQuestion.map { answerCount($0.id) } ?? 0
        return "Delete this question and its \(count) answer\(count == 1 ? "" : "s")?"
    }

    // MARK: - Row

    private func questionRow(question: SpaceQuestion) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
            HStack(alignment: .top, spacing: Constants.Spacing.xs) {
                TextField("Question", text: textBinding(for: question.id), axis: .vertical)
                    .lineLimit(1...4)

                if questions.count > 1 {
                    Button(role: .destructive) {
                        deleteQuestion(id: question.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.error)
                }
            }

            HStack {
                Text("\(question.text.count)/\(Constants.Limits.spaceQuestionTextMaxLength)")
                    .foregroundStyle(
                        question.text.count > Constants.Limits.spaceQuestionTextMaxLength
                            ? Color.error
                            : Color.secondary
                    )
                    .monospacedDigit()

                let rowAnswerCount = answerCount(question.id)
                if rowAnswerCount > 0 {
                    Spacer()
                    Text("\(rowAnswerCount) answer\(rowAnswerCount == 1 ? "" : "s")")
                        .foregroundStyle(Color.secondary)
                }
            }
            .font(.caption2)
        }
        .swipeActions(edge: .trailing) {
            if questions.count > 1 {
                Button(role: .destructive) {
                    deleteQuestion(id: question.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// Id-resolved text binding. Reads fall back to an empty string and writes no-op when the
    /// row has already been removed, so a delete can never index past the end of the array.
    private func textBinding(for id: String) -> Binding<String> {
        Binding(
            get: { questions.first { $0.id == id }?.text ?? "" },
            set: { newValue in
                guard let index = questions.firstIndex(where: { $0.id == id }) else { return }
                questions[index].text = newValue
            }
        )
    }

    private var addQuestionButton: some View {
        Button {
            addQuestion()
        } label: {
            Label("Add Question", systemImage: "plus.circle.fill")
        }
        .disabled(isAtLimit)
    }

    // MARK: - Actions

    private func addQuestion() {
        guard !isAtLimit else { return }
        questions.append(SpaceQuestion(id: UUID().uuidString, text: "", order: questions.count))
    }

    /// Routes through the confirmation dialog when the question already has answers;
    /// deletes immediately otherwise.
    private func deleteQuestion(id: String) {
        guard questions.count > 1 else { return }
        guard let question = questions.first(where: { $0.id == id }) else { return }
        if answerCount(question.id) > 0 {
            pendingDeleteQuestion = question
        } else {
            performDelete(id: id)
        }
    }

    private func performDelete(id: String) {
        questions.removeAll { $0.id == id }
        reindex()
    }

    private func delete(at offsets: IndexSet) {
        // Resolve to ids before touching the array, and skip offsets that no longer exist —
        // `onDelete` can fire with an index from a list state that has already changed.
        let ids = offsets.compactMap { questions.indices.contains($0) ? questions[$0].id : nil }
        guard questions.count > ids.count, let id = ids.first else { return }
        deleteQuestion(id: id)
    }

    private func move(from source: IndexSet, to destination: Int) {
        questions.move(fromOffsets: source, toOffset: destination)
        reindex()
    }

    private func reindex() {
        for index in questions.indices {
            questions[index].order = index
        }
    }
}

#Preview {
    @Previewable @State var questions: [SpaceQuestion] = [
        SpaceQuestion(id: "1", text: "What went well this week?", order: 0),
        SpaceQuestion(id: "2", text: "What could be improved?", order: 1)
    ]

    return Form {
        SpaceQuestionListEditor(questions: $questions)
    }
}
