import SwiftUI
import SwiftData

struct ReflectionDetailView: View {
    let reflection: Reflection

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showEditSheet = false
    @State private var showFullscreenImage: ImageAttachment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                // Learning Badge
                if let learning = reflection.learning {
                    learningBadge(learning)
                }

                // Title and Date
                headerSection

                // Hashtags
                if !reflection.hashtags.isEmpty {
                    hashtagSection
                }

                Divider()
                    .padding(.vertical, Constants.Spacing.xs)

                // Content
                contentSection

                // Images
                if !reflection.images.isEmpty {
                    imagesSection
                }

                // Voice Notes
                if !reflection.voiceRecordings.isEmpty {
                    voiceNotesSection
                }
            }
            .padding(Constants.Spacing.md)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .alert("Delete Reflection", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteReflection()
            }
        } message: {
            Text("Are you sure you want to delete this reflection? This action cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
        .fullScreenCover(item: $showFullscreenImage) { image in
            ImageFullscreenView(image: image)
        }
        .fullScreenCover(isPresented: $showEditSheet) {
            ReflectionEditorView(mode: .edit(reflection))
        }
    }

    // MARK: - Components

    private func learningBadge(_ learning: Learning) -> some View {
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            HStack {
                Text(reflection.title)
                    .font(.title.weight(.bold))

                Spacer()


            }

            Text(reflection.createdAt.formatted())
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var hashtagSection: some View {
        FlowLayout(spacing: Constants.Spacing.xs) {
            ForEach(reflection.hashtags) { hashtag in
                HashtagChip(text: hashtag.name, isSelected: false) {
                    // Navigate to filtered list
                }
            }
        }
    }

    private var contentSection: some View {
        Text(reflection.plainTextContent)
            .font(.body)
            .foregroundColor(.primary)
            .textSelection(.enabled)
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            SectionHeader("Images")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Constants.Spacing.sm) {
                    ForEach(reflection.images.sorted(by: { $0.sortOrder < $1.sortOrder })) { image in
                        imageCard(image)
                    }
                }
            }
        }
    }

    private func imageCard(_ image: ImageAttachment) -> some View {
        Button {
            showFullscreenImage = image
        } label: {
            Group {
                if let thumbnail = image.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))
        }
    }

    private var voiceNotesSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            SectionHeader("Voice Notes")

            ForEach(reflection.voiceRecordings.sorted(by: { $0.sortOrder < $1.sortOrder })) { recording in
                VoiceNotePlayer(voiceRecording: recording)
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
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

    // MARK: - Actions

    private var shareText: String {
        var text = "# \(reflection.title)\n\n"
        text += reflection.plainTextContent

        if !reflection.hashtags.isEmpty {
            text += "\n\n"
            text += reflection.hashtags.map { $0.displayName }.joined(separator: " ")
        }

        return text
    }

    private func copyText() {
        UIPasteboard.general.string = shareText
        HapticManager.shared.success()
    }

    private func deleteReflection() {
        modelContext.delete(reflection)
        try? modelContext.save()
        HapticManager.shared.success()
        dismiss()
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Image Fullscreen View

struct ImageFullscreenView: View {
    let image: ImageAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let uiImage = image.image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = value
                                }
                                .onEnded { _ in
                                    withAnimation {
                                        scale = 1.0
                                    }
                                }
                        )
                }
            }
            .background(Color.black)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    let reflection = Reflection(
        title: "My Learning Reflection",
        plainTextContent: "Today I learned about SwiftUI and SwiftData. It was really interesting to see how these frameworks work together."
    )

    NavigationStack {
        ReflectionDetailView(reflection: reflection)
    }
    .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
