import SwiftUI
import SwiftData
import UIKit

// MARK: - Media Grid Item Protocol

/// Protocol to unify different media types
protocol MediaGridItemProtocol: Identifiable {
    var gridThumbnailImage: UIImage? { get }
    var gridDuration: TimeInterval? { get }
}

// MARK: - Extensions for conformance
// Note: Using static helper methods instead of protocol extensions to avoid
// duplicate symbol linker errors with SwiftData @Model types

extension ImageAttachment {
    var gridThumbnailImage: UIImage? {
        if let thumbnailData = thumbnailData {
            return UIImage(data: thumbnailData)
        } else if let imageData = imageData {
            return UIImage(data: imageData)
        }
        return nil
    }
    var gridDuration: TimeInterval? { nil }
}

extension VideoAttachment {
    var gridThumbnailImage: UIImage? {
        guard let thumbnailData = thumbnailData else { return nil }
        return UIImage(data: thumbnailData)
    }
    var gridDuration: TimeInterval? { duration }
}

extension ImageInput: MediaGridItemProtocol {
    var gridThumbnailImage: UIImage? { image }
    var gridDuration: TimeInterval? { nil }
}

extension VideoInput: MediaGridItemProtocol {
    var gridThumbnailImage: UIImage? { thumbnailImage }
    var gridDuration: TimeInterval? { duration }
}

// MARK: - Type Erased Wrapper

struct AnyMediaGridItem: Identifiable {
    let id: UUID
    let _thumbnailImage: UIImage?
    let _duration: TimeInterval?

    var gridThumbnailImage: UIImage? { _thumbnailImage }
    var gridDuration: TimeInterval? { _duration }

    // Initialize from ImageAttachment
    init(_ item: ImageAttachment) {
        self.id = item.id
        self._thumbnailImage = item.gridThumbnailImage
        self._duration = item.gridDuration
    }

    // Initialize from VideoAttachment
    init(_ item: VideoAttachment) {
        self.id = item.id
        self._thumbnailImage = item.gridThumbnailImage
        self._duration = item.gridDuration
    }

    // Initialize from ImageInput
    init(_ item: ImageInput) {
        self.id = item.id
        self._thumbnailImage = item.gridThumbnailImage
        self._duration = item.gridDuration
    }

    // Initialize from VideoInput
    init(_ item: VideoInput) {
        self.id = item.id
        self._thumbnailImage = item.gridThumbnailImage
        self._duration = item.gridDuration
    }
}

// MARK: - Universal Media Grid

/// A unified grid view for displaying media attachments
struct UniversalMediaGridView: View {
    let items: [AnyMediaGridItem]
    let editable: Bool
    var onRemove: ((Int) -> Void)?
    var onTap: ((Int) -> Void)?

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
                            isVideo: item.gridDuration != nil,
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

struct UniversalMediaGridItem: View {
    let item: AnyMediaGridItem
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
                if let thumbnail = item.gridThumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: isVideo ? "video.fill" : "photo")
                                .foregroundStyle(.secondary)
                        }
                }

                // Play button overlay for videos
                if isVideo {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        )

                    // Duration badge
                    if let duration = item.gridDuration {
                        VStack {
                            Spacer()
                            HStack {
                                Text(durationText(from: duration))
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                                Spacer()
                            }
                        }
                        .padding(6)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
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
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(4)
            }
        }
    }

    private func durationText(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
