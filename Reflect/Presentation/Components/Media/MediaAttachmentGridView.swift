import SwiftUI
import SwiftData
import AVKit

// MARK: - Media Attachment Grid (Detail View)

/// Grid view for saved media attachments (used in ReflectionDetailView)
struct MediaAttachmentGridView: View {
    let images: [ImageAttachment]
    let videos: [VideoAttachment]
    let editable: Bool
    var onRemoveImage: ((ImageAttachment) -> Void)?
    var onRemoveVideo: ((VideoAttachment) -> Void)?
    var onImageTap: ((ImageAttachment) -> Void)?
    var onVideoTap: ((VideoAttachment) -> Void)?

    var body: some View {
        let imageItems: [AnyMediaGridItem] = images.map { AnyMediaGridItem($0) }
        let videoItems: [AnyMediaGridItem] = videos.map { AnyMediaGridItem($0) }
        let allItems = imageItems + videoItems
        return UniversalMediaGridView(
            items: allItems,
            editable: editable,
            onRemove: { index in
                if index < images.count {
                    onRemoveImage?(images[index])
                } else {
                    onRemoveVideo?(videos[index - images.count])
                }
            }, onTap: { index in
                if index < images.count {
                    onImageTap?(images[index])
                } else {
                    onVideoTap?(videos[index - images.count])
                }
            }
        )
    }
}

// MARK: - Editor Media Attachment Grid (Editor View)

/// Grid view for temporary media inputs (used in ReflectionEditorView)
struct EditorMediaAttachmentGridView: View {
    let images: [ImageInput]
    let videos: [VideoInput]
    var onRemoveImage: ((Int) -> Void)?
    var onRemoveVideo: ((Int) -> Void)?

    var body: some View {
        let imageItems: [AnyMediaGridItem] = images.map { AnyMediaGridItem($0) }
        let videoItems: [AnyMediaGridItem] = videos.map { AnyMediaGridItem($0) }
        let allItems = imageItems + videoItems
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
