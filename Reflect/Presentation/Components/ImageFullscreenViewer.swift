import SwiftUI

/// Display-only snapshot of an image shown by `ImageFullscreenViewer`.
/// Call sites map their own model (`ImageAttachment`, `ImageInput`) into this.
struct FullscreenImage: Identifiable {
    let id: UUID
    let image: UIImage?
}

/// Fullscreen image viewer shared by the reflection detail screen and the
/// editor. Supports pinch-to-zoom, swipe between images, and an optional
/// share action.
struct ImageFullscreenViewer: View {
    let images: [FullscreenImage]
    let showsShare: Bool
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var showShareSheet = false

    /// Identity-based start, for `.fullScreenCover(item:)` presentation.
    /// Falls back to the first image if `startingID` isn't found.
    init(images: [FullscreenImage], startingID: UUID, showsShare: Bool = false) {
        self.images = images
        self.showsShare = showsShare
        let index = images.firstIndex(where: { $0.id == startingID }) ?? 0
        _currentIndex = State(initialValue: index)
    }

    /// Index-based start, for `.fullScreenCover(isPresented:)` presentation.
    init(images: [FullscreenImage], startingIndex: Int = 0, showsShare: Bool = false) {
        self.images = images
        self.showsShare = showsShare
        _currentIndex = State(initialValue: startingIndex)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                let currentImage = images[currentIndex]
                if let uiImage = currentImage.image {
                    ZStack {
                        Color.black.ignoresSafeArea()

                        VStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                .gesture(
                                    DragGesture()
                                        .onEnded { value in
                                            if value.translation.width > 50 {
                                                if currentIndex > 0 {
                                                    withAnimation {
                                                        currentIndex -= 1
                                                        scale = 1.0
                                                    }
                                                }
                                            } else if value.translation.width < -50 {
                                                if currentIndex < images.count - 1 {
                                                    withAnimation {
                                                        currentIndex += 1
                                                        scale = 1.0
                                                    }
                                                }
                                            }
                                        }
                                )

                            HStack {
                                Spacer()
                                Text("\(currentIndex + 1)/\(images.count)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, Constants.Spacing.md)
                                    .padding(.vertical, Constants.Spacing.sm)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(.rect(cornerRadius: Constants.CornerRadius.small))
                                Spacer()
                            }
                            .padding(Constants.Spacing.md)
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.primaryDark)
                }

                if showsShare {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.primaryDark)
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showShareSheet) {
                if let currentImage = images[safe: currentIndex],
                   let image = currentImage.image {
                    ShareSheet(activityItems: [image])
                }
            }
        }
    }
}

// Helper for safe array access
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
