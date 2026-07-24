import SwiftUI
import UIKit

// MARK: - Universal Image Grid View

/// A reusable grid view for displaying images in a responsive layout
struct ImageGridView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var columns: Int = 2
    var spacing: CGFloat = 8
    var content: (Item, CGSize) -> Content

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(columns - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let itemSize = availableWidth / CGFloat(columns)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(itemSize), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(items) { item in
                    content(item, CGSize(width: itemSize, height: itemSize))
                }
            }
        }
    }
}

// MARK: - Attachment Grid View

/// Generic grid view for attachments (images, voice notes, etc.)
struct AttachmentGridView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var columns: Int = 2
    var spacing: CGFloat = 8
    var itemAspectRatio: CGFloat = 1.0
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(columns - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let itemWidth = availableWidth / CGFloat(columns)
            let itemHeight = itemWidth / itemAspectRatio

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(items) { item in
                    content(item)
                        .frame(width: itemWidth, height: itemHeight)
                }
            }
        }
        .frame(height: nil)
    }
}

// MARK: - ImageAttachment Grid View

/// Specialized grid for ImageAttachment models
struct ImageAttachmentGridView: View {
    let attachments: [ImageAttachment]
    var spacing: CGFloat = 8
    var onTap: ((ImageAttachment) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let columns = 2
            let totalSpacing = CGFloat(columns - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let itemSize = availableWidth / CGFloat(columns)

            LazyVGrid(
                columns: [
                    GridItem(.fixed(itemSize), spacing: spacing),
                    GridItem(.fixed(itemSize), spacing: spacing)
                ],
                spacing: spacing
            ) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    attachmentCard(attachment, size: itemSize)
                }
            }
        }
        .frame(height: nil)
    }

    private func attachmentCard(_ attachment: ImageAttachment, size: CGFloat) -> some View {
        Button {
            onTap?(attachment)
        } label: {
            Group {
                if let thumbnail = attachment.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Image Grid Item Component

struct ImageGridItem: View {
    let image: UIImage
    let size: CGSize
    var showRemoveButton: Bool = true
    var onTap: () -> Void
    var onRemove: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if showRemoveButton {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Removable Image Grid View

struct RemovableImageGridView: View {
    let images: [UIImage]
    var spacing: CGFloat = 8
    var onRemove: ((Int) -> Void)?
    var onTap: ((Int) -> Void)?

    @State private var targetSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let columns = 2
            let totalSpacing = CGFloat(columns - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let itemSize = availableWidth / CGFloat(columns)

            LazyVGrid(
                columns: [
                    GridItem(.fixed(itemSize), spacing: spacing),
                    GridItem(.fixed(itemSize), spacing: spacing)
                ],
                spacing: spacing
            ) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    ImageGridItem(
                        image: image,
                        size: CGSize(width: itemSize, height: itemSize),
                        showRemoveButton: onRemove != nil
                    ) {
                        if let onTap = onTap {
                            onTap(index)
                        }
                    } onRemove: {
                        onRemove?(index)
                    }
                }
            }
        }
        .frame(height: targetSize.width > 0 ? nil : 200)
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a responsive grid layout to the view
    func responsiveGrid(
        columns: Int = 2,
        spacing: CGFloat = 8
    ) -> some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(columns - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let itemSize = availableWidth / CGFloat(columns)

            self
                .frame(width: itemSize, height: itemSize)
        }
    }
}
