import SwiftUI
import SwiftData

struct ReflectionDetailView: View {
    let reflection: Reflection

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @State var showDeleteAlert = false
    @State var showShareSheet = false
    @State var showEditSheet = false
    @State var showFullscreenImage: ImageAttachment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let learning = reflection.learning {
                    learningBadge(learning)
                        .padding(.bottom, Constants.Spacing.md)
                }

                headerSection
                    .padding(.bottom, Constants.Spacing.md)

                if !reflection.hashtags.isEmpty {
                    hashtagSection
                        .padding(.bottom, Constants.Spacing.md)
                }

                Divider()
                    .opacity(0.3)
                    .padding(.bottom, Constants.Spacing.md)

                contentSection
                    .padding(.bottom, Constants.Spacing.md)

                if !reflection.voiceRecordings.isEmpty {
                    Divider()
                        .opacity(0.3)
                        .padding(.bottom, Constants.Spacing.md)

                    voiceNotesSection
                        .padding(.bottom, Constants.Spacing.md)
                }

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
        .fullScreenCover(isPresented: $showEditSheet) {
            ReflectionEditorView(mode: .edit(reflection))
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
