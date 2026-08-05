import SwiftUI

/// A single answer, styled for own vs others'. Context menu offers Edit/Delete (own, with a
/// delete confirmation) and Report (any). Delete also renders for a guest's answer when the
/// current user is the space owner — moderation affordance for App Clip submissions (AC-013).
/// Shows a photo thumbnail with a fullscreen viewer when the answer has an attached image.
struct AnswerBubble: View {
    let answer: SpaceAnswer
    let spaceName: String
    /// Whether the current user owns the space. Only relevant for guest answers — it's what
    /// lets the owner delete a guest's submission for moderation.
    var isSpaceOwner: Bool = false
    var onEdit: ((SpaceAnswer) -> Void)? = nil
    var onDelete: ((SpaceAnswer) -> Void)? = nil

    @State private var showImageFullscreen = false
    @State private var showDeleteConfirmation = false

    /// "You" styling and the own-answer highlight must never apply to a guest answer, even if
    /// `isMine` were ever true for one (defensive — see `SpaceAuthor`).
    private var showsAsMine: Bool { answer.isMine && !answer.isGuest }

    /// Delete renders for the author's own answer, or for a guest's answer if the current user
    /// owns the space. This mirrors (but does not replace) the trust-boundary guard in
    /// `DeleteOwnSpaceContentUseCase` — that guard is the actual enforcement point.
    private var canDelete: Bool {
        showsAsMine || (answer.isGuest && isSpaceOwner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(SpaceAuthor.label(
                    isMine: answer.isMine,
                    name: answer.isGuest ? answer.guestName : answer.authorDisplayName,
                    isGuest: answer.isGuest
                ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(showsAsMine ? Color.primaryDefault : .secondary)
                if let createdAt = answer.createdAt {
                    Text("·")
                    Text(createdAt, format: .relative(presentation: .named))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(answer.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let imageData = answer.imageData, let uiImage = UIImage(data: imageData) {
                Button {
                    showImageFullscreen = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 88, height: 88)
                        .clipShape(.rect(cornerRadius: Constants.CornerRadius.small))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attached photo")
                .fullScreenCover(isPresented: $showImageFullscreen) {
                    ImageFullscreenViewer(
                        images: [FullscreenImage(id: UUID(), image: uiImage)],
                        startingIndex: 0
                    )
                }
            }
        }
        .padding(Constants.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(showsAsMine ? Color.primaryDefault.opacity(0.10) : Color.secondary.opacity(0.08))
        )
        .contextMenu {
            if showsAsMine, let onEdit {
                Button { onEdit(answer) } label: { Label("Edit", systemImage: "pencil") }
            }
            if canDelete, onDelete != nil {
                Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
            }
            ReportContentButton(contentKind: "feedback", contentID: answer.id, spaceName: spaceName)
        }
        .confirmationDialog(
            "Delete this answer? This can't be undone.",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete?(answer) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
