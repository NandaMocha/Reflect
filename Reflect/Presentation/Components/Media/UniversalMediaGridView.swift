import SwiftUI
import SwiftData
import AVKit

// MARK: - Universal Media Grid Item

/// Protocol to unify different media types
protocol MediaGridItem: Identifiable {
    var thumbnailImage: UIImage? { get }
    var duration: TimeInterval? { get }
}

// MARK: - Extensions for conformance

extension ImageAttachment: MediaGridItem {
    var thumbnailImage: UIImage? {
        if let thumbnailData = thumbnailData {
            return UIImage(data: thumbnailData)
        } else if let imageData = imageData {
            return UIImage(data: imageData)
        }
        return nil
    }
    var duration: TimeInterval? { nil }
}

extension VideoAttachment: MediaGridItem {
    var thumbnailImage: UIImage? {
        guard let thumbnailData = thumbnailData else { return nil }
        return UIImage(data: thumbnailData)
    }
    var duration: TimeInterval? { self.duration }
}

extension ImageInput: MediaGridItem {
    var thumbnailImage: UIImage? { image }
    var duration: TimeInterval? { nil }
}

extension VideoInput: MediaGridItem {
    var thumbnailImage: UIImage? { thumbnailImage }
    var duration: TimeInterval? { duration }
}

// MARK: - Universal Media Attachment Grid

/// A unified grid view for displaying media attachments
/// Works with both saved attachments (ImageAttachment/VideoAttachment)
/// and temporary inputs (ImageInput/VideoInput)
struct UniversalMediaGridView<T: MediaGridItem>: View {
    let items: [T]
    let editable: Bool
    var onRemove: ((Int) -> Void)?
    var onTap: ((Int) -> Void)?

    var videos: [T] {
        items.compactMap { $0.duration != nil ? $0 : nil }
    }

    var body: some View {
        if items.isEmpty {
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
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        UniversalMediaGridItem(
                            item: item,
                            size: CGSize(width: itemSize, height: itemSize),
                            showRemoveButton: editable,
                            isVideo: item.duration != nil,
                            onTap: {
                                onTap?(index)
                            },
                            onRemove: {
                                onRemove?(index)
                            }
                        )
                    }
                }
            }
            .frame(height: nil)
        }
    }
}

// MARK: - Universal Media Grid Item

struct UniversalMediaGridItem<T: MediaGridItem>: View {
    let item: T
    let size: CGSize
    let showRemoveButton: Bool
    let isVideo: Bool
    var onTap: () -> Void
    var onRemove: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack {
                if let thumbnail = item.thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: isVideo ? "video.fill" : "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Play button overlay for videos
            if isVideo {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )

                // Duration badge
                if let duration = item.duration {
                    VStack {
                        Spacer()
                        HStack {
                            Text(durationText(from: duration))
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                            Spacer()
                        }
                    }
                    .padding(6)
                }
            }

            // Remove button
            if showRemoveButton {
                Button {
                    onRemove()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 28, height: 28)

                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(4)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func durationText(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Convenience Type Aliases

typealias SavedMediaGridView = UniversalMediaGridView<any Hashable>
typealias EditorMediaGridView = UniversalMediaGridView<any Hashable>

// MARK: - Detail View Helpers (removed, using universal component)

struct MediaAttachmentGridView: View {
    let images: [ImageAttachment]
    let videos: [VideoAttachment]
    let editable: Bool
    var onRemoveImage: ((ImageAttachment) -> Void)?
    var onRemoveVideo: ((VideoAttachment) -> Void)?
    var onImageTap: ((ImageAttachment) -> Void)?
    var onVideoTap: ((VideoAttachment) -> Void)?

    var body: some View {
        let allItems: [any MediaGridItem] = images + videos
        return UniversalMediaGridView(
            items: allItems,
            editable: editable,
            onTap: { index in
                if index < images.count {
                    onImageTap?(images[index])
                } else {
                    onVideoTap?(videos[index - images.count])
                }
            },
            onRemove: { index in
                if index < images.count {
                    onRemoveImage?(images[index])
                } else {
                    onRemoveVideo?(videos[index - images.count])
                }
            }
        )
    }
}

// MARK: - Editor View Helpers

struct EditorMediaAttachmentGridView: View {
    let images: [ImageInput]
    let videos: [VideoInput]
    var onRemoveImage: ((Int) -> Void)?
    var onRemoveVideo: ((Int) -> Void)?

    var body: some View {
        let allItems: [any MediaGridItem] = images + videos
        return UniversalMediaGridView(
            items: allItems,
            editable: true,
            onRemove: { index in
                if index < images.count {
                    onRemoveImage?(index)
                } else {
                    onRemoveVideo?(index - images.count)
                }
            }
        )
    }
}

// MARK: - Previews

#Preview("Universal Media Grid") {
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
        UniversalMediaGridView(
            items: [image, video].compactMap { $0 as? (any MediaGridItem) },
            editable: false,
            onTap: { _ in },
            onRemove: { _ in }
        )
    }
    .modelContainer(container ?? ModelContainer())
    .padding()
}
