import SwiftUI

/// Reusable editor for a feedback request's question list. Binds directly to an
/// `[SpaceQuestion]` array so both the create-space compose sheet (Phase 2) and the
/// post-creation "Edit questions" screen (Phase 5) can share one implementation.
///
/// Each row is a multiline `TextField` with a character counter, a delete button, and
/// drag-to-reorder (long-press, no `EditButton` required — SwiftUI's `List` supports this
/// natively once `.onMove` is attached). Reordering and deletion both rewrite `order` so it
/// always matches the array index.
struct SpaceQuestionListEditor: View {
    @Binding var questions: [SpaceQuestion]

    private var isAtLimit: Bool {
        questions.count >= Constants.Limits.spaceMaxQuestions
    }

    var body: some View {
        Section {
            ForEach($questions) { $question in
                questionRow(question: $question)
            }
            .onDelete(perform: delete)
            .onMove(perform: move)

            addQuestionButton
        } header: {
            Text("Questions")
        } footer: {
            Text("\(questions.count) of \(Constants.Limits.spaceMaxQuestions)")
        }
    }

    // MARK: - Row

    private func questionRow(question: Binding<SpaceQuestion>) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
            HStack(alignment: .top, spacing: Constants.Spacing.xs) {
                TextField("Question", text: question.text, axis: .vertical)
                    .lineLimit(1...4)

                if questions.count > 1 {
                    Button(role: .destructive) {
                        deleteQuestion(id: question.wrappedValue.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.error)
                }
            }

            Text("\(question.wrappedValue.text.count)/\(Constants.Limits.spaceQuestionTextMaxLength)")
                .font(.caption2)
                .foregroundStyle(
                    question.wrappedValue.text.count > Constants.Limits.spaceQuestionTextMaxLength
                        ? Color.error
                        : Color.secondary
                )
                .monospacedDigit()
        }
        .swipeActions(edge: .trailing) {
            if questions.count > 1 {
                Button(role: .destructive) {
                    deleteQuestion(id: question.wrappedValue.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
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

    private func deleteQuestion(id: String) {
        guard questions.count > 1 else { return }
        questions.removeAll { $0.id == id }
        reindex()
    }

    private func delete(at offsets: IndexSet) {
        guard questions.count > offsets.count else { return }
        questions.remove(atOffsets: offsets)
        reindex()
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
