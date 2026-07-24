import SwiftUI

struct EditorImageFullscreenView: View {
    let images: [ImageInput]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    init(images: [ImageInput], startingIndex: Int = 0) {
        self.images = images
        _currentIndex = State(initialValue: startingIndex)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                let currentImage = images[currentIndex]
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack {
                        Image(uiImage: currentImage.image)
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
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
