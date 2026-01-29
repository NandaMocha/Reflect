import SwiftUI

struct EditableImageCarouselView: View {
    @Binding var images: [ImageInput]
    let imageSize: CGFloat?
    let showIndicators: Bool
    let onImageRemoved: (() -> Void)?

    @State private var currentIndex = 0

    var body: some View {
        if images.isEmpty {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(spacing: Constants.Spacing.md) {
                // Carousel
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Constants.Spacing.md) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, imageInput in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: imageInput.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: imageSize ?? 250, height: imageSize ?? 250)
                                        .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))

                                    // Remove Button
                                    Button(action: {
                                        images.remove(at: index)
                                        if currentIndex >= images.count && currentIndex > 0 {
                                            currentIndex -= 1
                                        }
                                        onImageRemoved?()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                    }
                                    .padding(Constants.Spacing.sm)
                                }
                                .id(index)
                            }
                        }
                        .padding(.horizontal, Constants.Spacing.md)
                    }
                    .frame(height: imageSize ?? 250)
                    .onChange(of: currentIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                // Indicators
                if showIndicators && !images.isEmpty {
                    HStack(spacing: Constants.Spacing.xs) {
                        ForEach(0..<images.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? Color.primaryDefault : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }

                        Spacer()

                        Text("\(currentIndex + 1)/\(images.count)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, Constants.Spacing.md)
                }
            }
        )
    }
}

#Preview {
    @State var sampleImages = [
        ImageInput(image: UIImage(systemName: "photo")!),
        ImageInput(image: UIImage(systemName: "photo.fill")!),
        ImageInput(image: UIImage(systemName: "photo.stack")!)
    ]

    EditableImageCarouselView(
        images: $sampleImages,
        imageSize: 250,
        showIndicators: true
    )
}
