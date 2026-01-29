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
            VStack(alignment: .leading, spacing: 0) {
                // Learning Badge
                if let learning = reflection.learning {
                    learningBadge(learning)
                        .padding(.bottom, Constants.Spacing.md)
                }

                // Title and Date
                headerSection
                    .padding(.bottom, Constants.Spacing.md)

                // Hashtags
                if !reflection.hashtags.isEmpty {
                    hashtagSection
                        .padding(.bottom, Constants.Spacing.md)
                }

                Divider()
                    .opacity(0.3)
                    .padding(.bottom, Constants.Spacing.md)

                // Content
                contentSection
                    .padding(.bottom, Constants.Spacing.md)

                // Voice Notes
                if !reflection.voiceRecordings.isEmpty {
                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, Constants.Spacing.md)

                    voiceNotesSection
                        .padding(.bottom, Constants.Spacing.md)
                }

                // Images Gallery
                if !reflection.images.isEmpty {
                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, Constants.Spacing.md)

                    imagesGallery
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

    private var imagesGallery: some View {
        GeometryReader { geometry in
            let columns = 3
            let spacing = Constants.Spacing.xs
            let totalSpacing = CGFloat(columns - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let imageSize = availableWidth / CGFloat(columns)

            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(imageSize), spacing: spacing),
                        GridItem(.fixed(imageSize), spacing: spacing),
                        GridItem(.fixed(imageSize), spacing: spacing)
                    ],
                    spacing: spacing
                ) {
                    ForEach(reflection.images.sorted(by: { $0.sortOrder < $1.sortOrder })) { image in
                        imageCard(image, size: imageSize)
                    }
                }
            }
        }
        .frame(height: nil) // Let it size based on content
    }

    private func imageCard(_ image: ImageAttachment, size: CGFloat) -> some View {
        Button {
            showFullscreenImage = image
        } label: {
            Group {
                if let thumbnail = image.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.small))
        }
    }

    private var voiceNotesSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
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
