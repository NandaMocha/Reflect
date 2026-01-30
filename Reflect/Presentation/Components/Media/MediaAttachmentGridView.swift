import SwiftUI
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
                        MediaGridItem(
                            image: attachment.image,
                            video: nil,
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
                        MediaGridItem(
                            image: nil,
                            video: attachment,
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

// MARK: - Media Grid Item Component

struct MediaGridItem: View {
    let image: UIImage?
    let video: VideoAttachment?
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
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let video = video {
                    VideoThumbnailView(
                        thumbnail: video.thumbnail,
                        duration: video.duration,
                        size: size
                    )
                }

                // Play button overlay for videos
                if video != nil {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        )
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
                        EditorMediaGridItem(
                            image: input.image,
                            video: nil,
                            size: CGSize(width: itemSize, height: itemSize),
                            onRemove: {
                                onRemoveImage?(index)
                            }
                        )
                    }

                    // Videos
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, input in
                        EditorMediaGridItem(
                            image: nil,
                            video: input,
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

struct EditorMediaGridItem: View {
    let image: UIImage?
    let video: VideoInput?
    let size: CGSize
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let video = video {
                EditorVideoThumbnailView(
                    thumbnail: video.thumbnailImage,
                    duration: video.duration,
                    size: size
                )
            }

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

struct EditorVideoThumbnailView: View {
    let thumbnail: UIImage
    let duration: TimeInterval
    let size: CGSize

    var body: some View {
        ZStack {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()

            // Play button overlay
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                )
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
