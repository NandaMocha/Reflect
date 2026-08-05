import SwiftUI

/// A single answer, styled for own vs others'. Context menu offers Edit/Delete (own, with a
/// delete confirmation) and Report (any). Shows a photo thumbnail with a fullscreen viewer
/// when the answer has an attached image.
struct AnswerBubble: View {
    let answer: SpaceAnswer
    let spaceName: String
    var onEdit: ((SpaceAnswer) -> Void)? = nil
    var onDelete: ((SpaceAnswer) -> Void)? = nil

    @State private var showImageFullscreen = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(SpaceAuthor.label(isMine: answer.isMine, name: answer.authorDisplayName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(answer.isMine ? Color.primaryDefault : .secondary)
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
                .fill(answer.isMine ? Color.primaryDefault.opacity(0.10) : Color.secondary.opacity(0.08))
        )
        .contextMenu {
            if answer.isMine {
                if let onEdit {
                    Button { onEdit(answer) } label: { Label("Edit", systemImage: "pencil") }
                }
                if onDelete != nil {
                    Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
                }
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
