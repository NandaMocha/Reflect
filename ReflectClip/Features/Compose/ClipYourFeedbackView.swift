import SwiftUI

/// Enables `$viewModel.drafts[question.id, default: ""]` — SwiftUI's `Binding` only ships a
/// subscript for `Optional` dictionary values (`Binding<Value?>`), not one with a default, so
/// this fills that gap for the composer's per-question draft bindings.
fileprivate extension Binding {
    subscript<Key: Hashable, Element>(key: Key, default defaultValue: Element) -> Binding<Element> where Value == [Key: Element] {
        Binding<Element> {
            wrappedValue[key, default: defaultValue]
        } set: { newValue in
            wrappedValue[key] = newValue
        }
    }
}

/// The Clip's landing screen once a guest identity exists (`ClipSession.phase == .compose`).
/// Mirrors `Reflect/Presentation/Features/Space/Thread/SpaceThreadView.swift` conceptually
/// (reference only, never imported): a request header up top, one composer per question, and a
/// bottom submit bar — reimplemented here against the Clip-local `ClipSpaceRepository` /
/// `ClipFeedbackSubmitter` instead of the app's `SpaceCloudService`/`DIContainer`.
///
/// Uses only system semantic colors (`.tint`, `.secondary`) — `Color.primaryDefault` and friends
/// aren't shared into this target (see `Reflect/ClipShared/README.md`).
struct ClipYourFeedbackView: View {
    let session: ClipSession

    @State private var viewModel: ClipYourFeedbackViewModel
    @State private var showEditName = false
    @FocusState private var focusedQuestionId: String?
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40

    init(session: ClipSession) {
        self.session = session
        _viewModel = State(initialValue: ClipDIContainer.shared.makeClipYourFeedbackViewModel(session: session))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .loading:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .networkError(let message):
                    networkErrorView(message)
                case .loaded where !viewModel.hasQuestions:
                    emptyQuestionsView
                case .loaded:
                    composerContent(viewModel: viewModel)
                }
            }
            .navigationTitle("Your feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit name") {
                        showEditName = true
                    }
                    .accessibilityLabel("Edit your name")
                    .accessibilityValue(viewModel.displayName)
                }
            }
            .sheet(isPresented: $showEditName) {
                GuestNamePrompt(session: session, isEditMode: true)
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Loaded content

    private func composerContent(@Bindable viewModel: ClipYourFeedbackViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                    header
                    Divider()
                    ForEach(Array((viewModel.request?.questions ?? []).enumerated()), id: \.element.id) { index, question in
                        questionComposer(
                            index: index,
                            question: question,
                            text: $viewModel.drafts[question.id, default: ""]
                        )
                    }
                }
                .padding(Constants.Spacing.md)
            }

            submitBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(viewModel.request?.title ?? "")
                        .font(.title3.weight(.bold))
                        .lineLimit(3)

                    if let note = viewModel.request?.note, !note.isEmpty {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if let uiImage = viewModel.thumbnailImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: Constants.CornerRadius.medium))
                        .accessibilityLabel("Request thumbnail")
                }
            }

            if !viewModel.displayName.isEmpty {
                Text("Answering as \(viewModel.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func questionComposer(index: Int, question: SpaceQuestion, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text("Q\(index + 1). \(question.text)")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "Share your answer…",
                text: text,
                axis: .vertical
            )
            .lineLimit(3...10)
            .focused($focusedQuestionId, equals: question.id)
            .padding(Constants.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                    .fill(Color.secondary.opacity(0.12))
            )
            .accessibilityLabel("Your answer to question \(index + 1): \(question.text)")
            .accessibilityValue(
                "\(text.wrappedValue), \(viewModel.draftLength(for: question.id)) of \(ClipYourFeedbackViewModel.answerMaxLength) characters"
            )

            HStack {
                Spacer()
                Text("\(viewModel.draftLength(for: question.id))/\(ClipYourFeedbackViewModel.answerMaxLength)")
                    .font(.caption)
                    .fontWeight(viewModel.isOverLimit(for: question.id) ? .bold : .regular)
                    .foregroundStyle(viewModel.isOverLimit(for: question.id) ? .red : .secondary)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }

            if viewModel.isOverLimit(for: question.id) {
                Text("This answer is too long — trim it to \(ClipYourFeedbackViewModel.answerMaxLength) characters.")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Divider()

            if let message = viewModel.submitErrorMessage {
                submitErrorBanner(message)
            }

            HStack {
                if viewModel.isSubmitting {
                    ProgressView()
                    Text("Sending…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Button {
                        focusedQuestionId = nil
                        Task { await viewModel.submit() }
                    } label: {
                        Text("Send Feedback")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSubmit)
                }
            }
        }
        .padding(Constants.Spacing.md)
        .background(.bar)
    }

    private func submitErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Constants.Spacing.xs) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not sent yet")
                    .font(.caption.weight(.semibold))
                Text("\(message) Your answer is saved and will send when you're back online.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Retry") {
                Task { await viewModel.retrySubmit() }
            }
            .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Other load states

    private func networkErrorView(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.lg) {
                VStack(spacing: Constants.Spacing.sm) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: iconSize))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Couldn't load this request")
                        .font(.title2.bold())
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Try Again") {
                    Task { await viewModel.retryLoad() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(Constants.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var emptyQuestionsView: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.sm) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("No questions yet")
                    .font(.title2.bold())
                Text("This request doesn't have any questions to answer right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Constants.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
