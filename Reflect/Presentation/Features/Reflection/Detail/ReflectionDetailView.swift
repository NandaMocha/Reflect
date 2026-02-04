import SwiftUI
import SwiftData
import AVKit

struct ReflectionDetailView: View {
    let reflection: Reflection

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @State var showDeleteAlert = false
    @State var showShareSheet = false
    @State var showEditSheet = false
    @State var showFullscreenImage: ImageAttachment?
    @State var showFullscreenVideo: VideoAttachment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let learning = reflection.learning {
                    learningBadge(learning)
                        .padding(.bottom, Constants.Spacing.md)
                }

                headerSection
                    .padding(.bottom, Constants.Spacing.md)

                Divider()
                    .opacity(0.3)
                    .padding(.bottom, Constants.Spacing.md)

                if !reflection.plainTextContent.isEmpty {
                    contentSection
                        .padding(.bottom, Constants.Spacing.md)
                    
                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, Constants.Spacing.md)
                }

                if !reflection.voiceRecordings.isEmpty {
                    voiceNotesSection
                        .padding(.bottom, Constants.Spacing.md)
                    
                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, Constants.Spacing.md)
                }

                // Show media gallery if there are images or videos
                if !reflection.images.isEmpty || !reflection.videos.isEmpty {
                    mediaGallery
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
        .deleteConfirmationAlert(
            itemName: "Reflection",
            isPresented: $showDeleteAlert,
            additionalMessage: "Are you sure you want to delete this reflection? This action cannot be undone."
        ) {
            deleteReflection()
        }
        .sheet(isPresented: $showShareSheet) {
            ReflectionShareSheet(items: [shareText])
        }
        .fullScreenCover(item: $showFullscreenImage) { image in
            ReflectionImageFullscreenView(
                images: reflection.images.sorted(by: { $0.sortOrder < $1.sortOrder }),
                startingImage: image
            )
        }
        .fullScreenCover(item: $showFullscreenVideo) { video in
            if let videoData = video.videoData {
                VideoPlayerView(videoData: videoData)
            }
        }
        .fullScreenCover(isPresented: $showEditSheet) {
            ReflectionEditorView(mode: .edit(reflection), onDismiss: {
                // Dismiss detail view after saving edit
                dismiss()
            })
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
