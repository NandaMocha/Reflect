import SwiftUI
import StoreKit
import UIKit

/// The Clip's "All feedback" screen (`ClipSession.phase == .allFeedback`), reached after a
/// successful submit. Mirrors
/// `Reflect/Presentation/Features/Space/Thread/SpaceAllResponsesView.swift` conceptually
/// (reference only, never imported): a question segmented picker when there's more than one
/// question, answers grouped by question, pull-to-refresh — reimplemented here against the
/// Clip-local `ClipSpaceRepository`/`PendingAnswerStore` instead of the app's `SpaceThreadViewModel`.
///
/// Uses only system semantic colors — `Color.primaryDefault` and friends aren't shared into this
/// target (see `Reflect/ClipShared/README.md`).
struct ClipAllFeedbackView: View {
    let session: ClipSession

    @State private var viewModel: ClipAllFeedbackViewModel
    @State private var selectedQuestionId: String = ""
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40

    init(session: ClipSession) {
        self.session = session
        _viewModel = State(initialValue: ClipDIContainer.shared.makeClipAllFeedbackViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .loading:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .networkError(let message):
                    networkErrorView(message)
                case .loaded:
                    loadedContent
                }
            }
            .navigationTitle("All feedback")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .onChange(of: viewModel.questions, initial: true) { _, questions in
                if !questions.contains(where: { $0.id == selectedQuestionId }) {
                    selectedQuestionId = questions.first?.id ?? ""
                }
            }
            .onAppear { presentInstallOverlayIfNeeded() }
        }
    }

    // MARK: - Install Overlay (AC-040)

    /// Fires the `SKOverlay` install upsell once, after the guest's first successful submit —
    /// see `ClipAllFeedbackViewModel.presentInstallOverlayIfNeeded()` for the actual gating
    /// (App Group-persisted flag + "at least one answer reached `.sent`"). Presentation itself
    /// (finding the active `UIWindowScene`) lives here rather than in the view model since
    /// `SKOverlay` is a UIKit-facing API with no SwiftUI equivalent.
    ///
    /// No-ops in the iOS Simulator by design (`SKOverlay` itself no-ops there) — see AC-040's
    /// watch-out; this is verified for real on-device in AC-H4.
    private func presentInstallOverlayIfNeeded() {
        Task {
            guard await viewModel.presentInstallOverlayIfNeeded() else { return }
            guard let windowScene = Self.activeWindowScene() else { return }
            let overlay = SKOverlay(configuration: SKOverlay.AppClipConfiguration(position: .bottom))
            overlay.present(in: windowScene)
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    // MARK: - Loaded content

    private var loadedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                questionFilterHeader

                if items.isEmpty {
                    Text(viewModel.hasAnyFeedback ? "No answers to this question yet." : "No feedback yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Constants.Spacing.xl)
                } else {
                    ForEach(items) { item in
                        ClipAnswerBubble(item: item, requestTitle: viewModel.request?.title ?? "", session: session)
                    }
                }

                if let refreshErrorMessage = viewModel.refreshErrorMessage {
                    refreshErrorBanner(refreshErrorMessage)
                }

                footerNote
            }
            .padding(Constants.Spacing.md)
        }
        .refreshable { await viewModel.refresh() }
    }

    private var items: [ClipFeedbackItem] {
        guard !selectedQuestionId.isEmpty else { return [] }
        return viewModel.items(for: selectedQuestionId)
    }

    @ViewBuilder
    private var questionFilterHeader: some View {
        let questions = viewModel.questions
        if questions.count > 1 {
            Picker("Question", selection: $selectedQuestionId) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    Text("Q\(index + 1)")
                        .tag(question.id)
                        .accessibilityLabel(question.text)
                }
            }
            .pickerStyle(.segmented)

            if let selectedQuestion = questions.first(where: { $0.id == selectedQuestionId }) {
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

    /// Honest copy per AC-032's decision (plan review): never claims a background retry loop is
    /// running (none exists yet — see `docs/features/app-clip-tasks.md`) — only describes what
    /// actually happens, that delivery depends on the owner's device syncing.
    private var footerNote: some View {
        Text("Answers you send are saved on this device right away. They may take a little while to show up here for everyone, since the owner's device needs to be online to receive them.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Constants.Spacing.xs)
    }

    private func refreshErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Constants.Spacing.xs) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    Text("Couldn't load feedback")
                        .font(.title2.bold())
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Try Again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(Constants.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
