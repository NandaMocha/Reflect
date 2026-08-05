import SwiftUI

/// One answer bubble in `ClipAllFeedbackView`. Mirrors
/// `Reflect/Presentation/Features/Space/Thread/AnswerBubble.swift` conceptually (reference only,
/// never imported) but reimplemented against `ClipFeedbackItem` instead of a bare `SpaceAnswer`,
/// since a Clip guest also needs to see their own not-yet-confirmed answers.
///
/// No Edit/Delete here — those are full-app moderation/composer affordances outside AC-032's
/// scope. Report is offered only for mirror-confirmed answers: a still-pending local draft has no
/// server-side record yet, so there's nothing for the owner to look up if reported.
///
/// Uses only system semantic colors (`.secondary`, `.orange`, `.red`) — `Color.primaryDefault`
/// and friends aren't shared into this target (see `Reflect/ClipShared/README.md`).
struct ClipAnswerBubble: View {
    let item: ClipFeedbackItem
    let requestTitle: String
    let session: ClipSession

    /// Destination for reports, matching `ReportContentButton`'s address.
    private let reportEmail = "nanda.mocha@gmail.com"

    @State private var showNoMailAlert = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch item {
        case .confirmed(let answer):
            confirmedBubble(answer)
        case .pending(let pending):
            pendingBubble(pending)
        }
    }

    // MARK: - Confirmed

    private func confirmedBubble(_ answer: SpaceAnswer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            bylineRow(for: answer)
                .font(.caption)
                .foregroundStyle(answer.isMine ? .primary : .secondary)

            Text(answer.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Constants.Spacing.sm)
        .background(bubbleBackground(highlighted: answer.isMine))
        .contextMenu {
            Button(role: .destructive) {
                openReportMail(contentID: answer.id)
            } label: {
                Label("Report…", systemImage: "exclamationmark.bubble")
            }
        }
        .alert("Can't open Mail", isPresented: $showNoMailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Email \(reportEmail) to report this feedback.")
        }
        // Without this, Report is reachable only via direct touch + long-press on the
        // `.contextMenu` above — VoiceOver/Voice Control/Switch Control users have no way to
        // reach it. Matches `pendingBubble`'s `.accessibilityElement(children: .combine)` pattern.
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Report") {
            openReportMail(contentID: answer.id)
        }
    }

    /// Guest name (up to 50 chars) + "·" + relative date. A plain non-wrapping `HStack` truncates
    /// at large Dynamic Type sizes, so `ViewThatFits` falls back to a two-line `VStack` when the
    /// single-line layout doesn't fit instead of clipping the byline.
    private func bylineRow(for answer: SpaceAnswer) -> some View {
        ViewThatFits {
            HStack(spacing: 4) {
                Text(byline(for: answer))
                    .font(.caption.weight(.semibold))
                if let createdAt = answer.createdAt {
                    Text("·")
                    Text(createdAt, format: .relative(presentation: .named))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(byline(for: answer))
                    .font(.caption.weight(.semibold))
                if let createdAt = answer.createdAt {
                    Text(createdAt, format: .relative(presentation: .named))
                }
            }
        }
    }

    private func byline(for answer: SpaceAnswer) -> String {
        if answer.isMine { return "You" }
        return answer.guestName ?? answer.authorDisplayName ?? "Member"
    }

    // MARK: - Pending

    private func pendingBubble(_ pending: PendingAnswer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("You")
                    .font(.caption.weight(.semibold))
                Text("·")
                Text(pendingStatusLabel(for: pending.state))
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(pendingStatusColor(for: pending.state))

            Text(pending.body)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            if pending.state == .queued {
                Button("Go back and retry") {
                    session.returnToCompose()
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(Constants.Spacing.sm)
        .background(bubbleBackground(highlighted: true))
        // Honest per AC-032's decision: no automatic-retry claim here — see
        // `ClipAllFeedbackView`'s footer note for the delivery-timing copy.
        .accessibilityElement(children: .combine)
    }

    /// Honest, state-specific copy — never implies a background retry process is running (none
    /// exists yet, see `docs/features/app-clip-tasks.md` AC-032's watch-outs).
    private func pendingStatusLabel(for state: PendingAnswer.State) -> String {
        switch state {
        case .queued:
            return "Saved on this device — not sent yet"
        case .sent:
            return "Waiting for the owner to sync"
        case .failed:
            return "Couldn't be delivered"
        }
    }

    /// `.queued` (never delivered, needs the guest to retry) reads as more urgent than `.sent`
    /// (delivered, just waiting on the owner's next sync) — both stay plain system semantic
    /// colors since `Color.error`/`Color.primaryDefault` aren't shared into this target.
    private func pendingStatusColor(for state: PendingAnswer.State) -> Color {
        switch state {
        case .queued:
            return .orange
        case .sent:
            return .secondary
        case .failed:
            return .red
        }
    }

    // MARK: - Shared

    private func bubbleBackground(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
            .fill(highlighted ? AnyShapeStyle(.tint.opacity(0.10)) : AnyShapeStyle(Color.secondary.opacity(0.08)))
    }

    /// Reimplemented Clip-side rather than importing `ReportContentButton` — that type lives
    /// under `Reflect/Presentation/`, outside anything shared into `ReflectClip` (see
    /// `Reflect/ClipShared/README.md`'s purity rule).
    private func openReportMail(contentID: String) {
        let subject = "Report feedback in \(requestTitle)"
        let body = """
        I'd like to report this feedback.

        Request: \(requestTitle)
        Content ID: \(contentID)

        Reason:

        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else {
            showNoMailAlert = true
            return
        }
        openURL(url) { accepted in
            if !accepted { showNoMailAlert = true }
        }
    }
}
