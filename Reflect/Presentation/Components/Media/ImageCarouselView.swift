import SwiftUI

struct ImageCarouselView: View {
    let images: [UIImage]
    let imageSize: CGFloat?
    let showIndicators: Bool

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
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: imageSize ?? 300, height: imageSize ?? 300)
                                    .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, Constants.Spacing.md)
                    }
                    .frame(height: imageSize ?? 300)
                    .onChange(of: currentIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                // Indicators
                if showIndicators {
                    HStack(spacing: Constants.Spacing.xs) {
                        Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .opacity(currentIndex > 0 ? 1.0 : 0.3)
                        }
                        .disabled(currentIndex == 0)

                        Spacer()

                        ForEach(0..<images.count, id: \.self) { index in
                            Button(action: { currentIndex = index }) {
                                Circle()
                                    .fill(index == currentIndex ? Color.primaryDefault : Color.secondary.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }

                        Spacer()

                        Button(action: { if currentIndex < images.count - 1 { currentIndex += 1 } }) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .opacity(currentIndex < images.count - 1 ? 1.0 : 0.3)
                        }
                        .disabled(currentIndex >= images.count - 1)
                    }
                    .padding(.horizontal, Constants.Spacing.md)
                }
            }
        )
    }
}

#Preview {
    let sampleImages = [
        UIImage(systemName: "photo")!,
        UIImage(systemName: "photo.fill")!,
        UIImage(systemName: "photo.stack")!
    ]

    ImageCarouselView(
        images: sampleImages,
        imageSize: 250,
        showIndicators: true
    )
}
