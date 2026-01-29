import SwiftUI

// MARK: - View Components Extension

extension ReflectionDetailView {
    func learningBadge(_ learning: Learning) -> some View {
        NavigationLink(destination: FilteredReflectionListView(learning: learning)) {
            HStack(spacing: Constants.Spacing.xs) {
                Image(systemName: learning.iconName)
                    .font(.caption)
                Text(learning.title)
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(Color(hex: learning.colorHex))
            .padding(.horizontal, Constants.Spacing.sm)
            .padding(.vertical, Constants.Spacing.xs)
            .background(
                Capsule()
                    .fill(Color(hex: learning.colorHex).opacity(0.15))
            )
        }
    }

    var headerSection: some View {
        DetailSectionHeader(
            title: reflection.title,
            date: reflection.createdAt
        )
    }

    var contentSection: some View {
        Text(reflection.plainTextContent)
            .font(.body)
            .foregroundColor(.primary)
            .textSelection(.enabled)
    }

    var imagesGallery: some View {
        ImageAttachmentGridView(
            attachments: reflection.images.sorted(by: { $0.sortOrder < $1.sortOrder })
        ) { image in
            showFullscreenImage = image
        }
    }

    var voiceNotesSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            ForEach(reflection.voiceRecordings.sorted(by: { $0.sortOrder < $1.sortOrder })) { recording in
                VoiceNotePlayer(voiceRecording: recording)
            }
        }
    }

    @ViewBuilder
    var menuItems: some View {
        Button {
            showShareSheet = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button {
            copyText()
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
