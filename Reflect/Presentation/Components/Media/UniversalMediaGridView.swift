import SwiftUI
import SwiftData
import AVKit

// MARK: - Media Grid Item Protocol

/// Protocol to unify different media types
protocol MediaGridItemProtocol: Identifiable {
    var thumbnailImage: UIImage? { get }
    var duration: TimeInterval? { get }
    var id: UUID { get }
}

// MARK: - Extensions for conformance

extension ImageAttachment: MediaGridItemProtocol {
    var thumbnailImage: UIImage? {
        if let thumbnailData = thumbnailData {
            return UIImage(data: thumbnailData)
        } else if let imageData = imageData {
            return UIImage(data: imageData)
        }
        return nil
    }
    var duration: TimeInterval? { nil }
    var id: UUID { self.id }
}

extension VideoAttachment: MediaGridItemProtocol {
    var thumbnailImage: UIImage? {
        guard let thumbnailData = thumbnailData else { return nil }
        return UIImage(data: thumbnailData)
    }
    var duration: TimeInterval? { self.duration }
    var id: UUID { self.id }
}

extension ImageInput: MediaGridItemProtocol {
    var thumbnailImage: UIImage? { image }
    var duration: TimeInterval? { nil }
    var id: UUID { self.id }
}

extension VideoInput: MediaGridItemProtocol {
    var thumbnailImage: UIImage? { thumbnailImage }
    var duration: TimeInterval? { duration }
    var id: UUID { self.id }
}

// MARK: - Type Erased Wrapper

struct AnyMediaGridItem: Identifiable, MediaGridItemProtocol {
    let _id: UUID
    let _thumbnailImage: UIImage?
    let _duration: TimeInterval?

    var id: UUID { _id }
    var thumbnailImage: UIImage? { _thumbnailImage }
    var duration: TimeInterval? { _duration }

    init<T: MediaGridItemProtocol>(_ item: T) {
        self._id = item.id
        self._thumbnailImage = item.thumbnailImage
        self._duration = item.duration
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
