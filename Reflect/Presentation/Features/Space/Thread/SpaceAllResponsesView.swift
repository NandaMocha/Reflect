import SwiftUI

/// The full answer list for a reflection — everyone's, including yours, across every
/// question. Own answers can be deleted (edit happens back on the respond page, via
/// selecting the question); every answer can be reported.
struct SpaceAllResponsesView: View {
    @Bindable var viewModel: SpaceThreadViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestionId: String?
    @State private var showExportOptions = false
    @State private var showShareSheet = false

    init(viewModel: SpaceThreadViewModel) {
        self.viewModel = viewModel
        _selectedQuestionId = State(initialValue: viewModel.reflection.questions.first?.id)
    }

    private var selectedQuestion: SpaceQuestion? {
        viewModel.reflection.questions.first { $0.id == selectedQuestionId }
    }

    private var filteredAnswers: [SpaceAnswer] {
        guard let selectedQuestionId else { return [] }
        return viewModel.answers(for: selectedQuestionId)
    }

    @ViewBuilder
    private var questionFilterHeader: some View {
        let questions = viewModel.reflection.questions
        if questions.count > 1 {
            Picker("Question", selection: $selectedQuestionId) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    Text("Q\(index + 1)").tag(question.id as String?)
                }
            }
            .pickerStyle(.segmented)

            if let selectedQuestion {
                Text(selectedQuestion.text)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let question = questions.first {
            Text(question.text)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                questionFilterHeader

                if filteredAnswers.isEmpty {
                    Text(viewModel.answers.isEmpty ? "No feedback yet." : "No answers to this question yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Constants.Spacing.xl)
                } else {
                    ForEach(filteredAnswers) { answer in
                        // Edit/Delete only render for own answers (guarded by `answer.isMine`
                        // inside `AnswerBubble`), so passing them for every row is safe.
                        let questionNumber = (viewModel.reflection.questions.firstIndex(where: { $0.id == answer.questionId }) ?? 0) + 1
                        AnswerBubble(
                            answer: answer,
                            spaceName: viewModel.space.name,
                            questionNumber: questionNumber,
                            onEdit: {
                                viewModel.select(questionId: answer.questionId)
                                dismiss()
                            },
                            onDelete: { Task { await viewModel.deleteOwnAnswer(for: answer.questionId) } }
                        )
                    }
                }
            }
            .padding(Constants.Spacing.md)
        }
        .navigationTitle("All feedback")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        // The owner can delete a question from the edit sheet while this filter is pointed at
        // it; without this the segmented picker holds a dead tag and the list reads empty.
        .onChange(of: viewModel.reflection.questions) { _, questions in
            if !questions.contains(where: { $0.id == selectedQuestionId }) {
                selectedQuestionId = questions.first?.id
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showExportOptions = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export feedback")
            }
        }
        .confirmationDialog("Export feedback", isPresented: $showExportOptions, titleVisibility: .visible) {
            Button("Export as JSON") { Task { await viewModel.export(format: .json) } }
            Button("Export as CSV") { Task { await viewModel.export(format: .csv) } }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: viewModel.exportedFileURL) { _, url in
            showShareSheet = url != nil
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ReflectionShareSheet(items: [url])
            }
        }
        .errorAlert($viewModel.errorMessage)
    }
}
