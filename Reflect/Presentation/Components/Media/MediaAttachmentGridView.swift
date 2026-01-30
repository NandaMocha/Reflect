import SwiftUI
import SwiftData
import AVKit

// MARK: - Universal Media Attachment Grid

/// A unified grid view for displaying media attachments (images and videos)
/// Used in both ReflectionDetailView and ReflectionEditorView
struct MediaAttachmentGridView: View {
    let images: [ImageAttachment]
    let videos: [VideoAttachment]
    let editable: Bool
    var onRemoveImage: ((ImageAttachment) -> Void)?
    var onRemoveVideo: ((VideoAttachment) -> Void)?
    var onImageTap: ((ImageAttachment) -> Void)?
    var onVideoTap: ((VideoAttachment) -> Void)?

    var body: some View {
        if images.isEmpty && videos.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geometry in
                let columns = 2
                let totalSpacing = CGFloat(columns - 1) * 8
                let availableWidth = geometry.size.width - totalSpacing
                let itemSize = availableWidth / CGFloat(columns)

                LazyVGrid(
                    columns: [
                        GridItem(.fixed(itemSize), spacing: 8),
                        GridItem(.fixed(itemSize), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    // Images
                    ForEach(images) { attachment in
                        MediaImageGridItem(
                            attachment: attachment,
                            size: CGSize(width: itemSize, height: itemSize),
                            showRemoveButton: editable,
                            onTap: {
                                onImageTap?(attachment)
                            },
                            onRemove: {
                                onRemoveImage?(attachment)
                            }
                        )
                    }

                    // Videos
                    ForEach(videos) { attachment in
                        MediaVideoGridItem(
                            attachment: attachment,
                            size: CGSize(width: itemSize, height: itemSize),
                            showRemoveButton: editable,
                            onTap: {
                                onVideoTap?(attachment)
                            },
                            onRemove: {
                                onRemoveVideo?(attachment)
                            }
                        )
                    }
                }
            }
            .frame(height: nil)
        }
    }
}

// MARK: - Media Image Grid Item

struct MediaImageGridItem: View {
    let attachment: ImageAttachment
    let size: CGSize
    let showRemoveButton: Bool
    var onTap: () -> Void
    var onRemove: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .topTrailing) {
                // Content
                if let imageData = attachment.imageData,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let thumbnailData = attachment.thumbnailData,
                          let thumbnail = UIImage(data: thumbnailData) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }

                // Remove button (only in edit mode)
                if showRemoveButton {
                    Button {
                        onRemove()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 24, height: 24)

                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .offset(x: 5, y: -5)
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Media Video Grid Item

struct MediaVideoGridItem: View {
    let attachment: VideoAttachment
    let size: CGSize
    let showRemoveButton: Bool
    var onTap: () -> Void
    var onRemove: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .topTrailing) {
                // Thumbnail
                if let thumbnailData = attachment.thumbnailData,
                   let thumbnail = UIImage(data: thumbnailData) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            Image(systemName: "video.fill")
                                .foregroundColor(.secondary)
                        }
                }

                // Play button overlay
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    )

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Text(durationText)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                        Spacer()
                    }
                }
                .padding(6)

                // Remove button (only in edit mode)
                if showRemoveButton {
                    Button {
                        onRemove()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 24, height: 24)

                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .offset(x: 5, y: -5)
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var durationText: String {
        let minutes = Int(attachment.duration) / 60
        let seconds = Int(attachment.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Thumbnail View

struct VideoThumbnailView: View {
    let thumbnail: UIImage?
    let duration: TimeInterval
    let size: CGSize

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "video.fill")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Text(durationText)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                    Spacer()
                }
            }
            .padding(6)
        )
    }

    private var durationText: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Editor Media Grid (for ImageInput and VideoInput)

/// Grid view for editor with ImageInput and VideoInput (temporary data before save)
struct EditorMediaAttachmentGridView: View {
    let images: [ImageInput]
    let videos: [VideoInput]
    var onRemoveImage: ((Int) -> Void)?
    var onRemoveVideo: ((Int) -> Void)?

    var body: some View {
        if images.isEmpty && videos.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geometry in
                let columns = 2
                let totalSpacing = CGFloat(columns - 1) * 8
                let availableWidth = geometry.size.width - totalSpacing
                let itemSize = availableWidth / CGFloat(columns)

                LazyVGrid(
                    columns: [
                        GridItem(.fixed(itemSize), spacing: 8),
                        GridItem(.fixed(itemSize), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    // Images
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, input in
                        EditorMediaImageGridItem(
                            input: input,
                            size: CGSize(width: itemSize, height: itemSize),
                            onRemove: {
                                onRemoveImage?(index)
                            }
                        )
                    }

                    // Videos
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, input in
                        EditorMediaVideoGridItem(
                            input: input,
                            size: CGSize(width: itemSize, height: itemSize),
                            onRemove: {
                                onRemoveVideo?(index)
                            }
                        )
                    }
                }
            }
            .frame(height: nil)
        }
    }
}

// MARK: - Editor Media Image Grid Item

struct EditorMediaImageGridItem: View {
    let input: ImageInput
    let size: CGSize
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: input.image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Remove button
            Button {
                onRemove()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 24, height: 24)

                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(x: 5, y: -5)
        }
    }
}

// MARK: - Editor Media Video Grid Item

struct EditorMediaVideoGridItem: View {
    let input: VideoInput
    let size: CGSize
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: input.thumbnailImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Play button overlay
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                )

            // Duration badge
            VStack {
                Spacer()
                HStack {
                    Text(durationText)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                    Spacer()
                }
            }
            .padding(6)

            // Remove button
            Button {
                onRemove()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 24, height: 24)

                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(x: 5, y: -5)
        }
    }

    private var durationText: String {
        let minutes = Int(input.duration) / 60
        let seconds = Int(input.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}


#Preview("Media Attachment Grid - Detail View") {
    let container = try? ModelContainer(for: ImageAttachment.self, VideoAttachment.self, inMemory: true)

    let image = ImageAttachment(
        imageData: UIImage(systemName: "photo")?.jpegData(compressionQuality: 1),
        thumbnailData: nil
    )

    let video = VideoAttachment(
        videoData: nil,
        thumbnailData: UIImage(systemName: "video.fill")?.jpegData(compressionQuality: 1),
        duration: 45
    )

    return ScrollView {
        MediaAttachmentGridView(
            images: [image].compactMap { $0 },
            videos: [video].compactMap { $0 },
            editable: false,
            onImageTap: { _ in },
            onVideoTap: { _ in }
        )
        .padding()
    }
    .modelContainer(container ?? ModelContainer())
}

#Preview("Editor Media Grid - Editor View") {
    EditorMediaAttachmentGridView(
        images: [
            ImageInput(image: UIImage(systemName: "photo")!),
            ImageInput(image: UIImage(systemName: "camera")!)
        ],
        videos: [
            VideoInput(
                videoURL: URL(fileURLWithPath: "/"),
                thumbnailImage: UIImage(systemName: "video.fill")!,
                duration: 60
            )
        ],
        onRemoveImage: { _ in },
        onRemoveVideo: { _ in }
    )
    .padding()
}
