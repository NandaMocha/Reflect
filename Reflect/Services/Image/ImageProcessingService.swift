import Foundation
import UIKit

class ImageProcessingService: ImageProcessingServiceProtocol {
    static let shared = ImageProcessingService()

    private init() {}

    func compressImage(_ image: UIImage, quality: CompressionQuality) -> Data? {
        let maxDimension: CGFloat = quality == .low ? 800 : (quality == .medium ? 1200 : 1600)
        guard let resized = resizeImage(image, maxDimension: maxDimension) else {
            return image.jpegData(compressionQuality: quality.jpegQuality)
        }
        return resized.jpegData(compressionQuality: quality.jpegQuality)
    }

    func generateThumbnail(_ image: UIImage, size: CGSize) -> Data? {
        let aspectWidth = size.width / image.size.width
        let aspectHeight = size.height / image.size.height
        let aspectRatio = min(aspectWidth, aspectHeight)

        let scaledSize = CGSize(
            width: image.size.width * aspectRatio,
            height: image.size.height * aspectRatio
        )

        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: scaledSize))
        }

        return thumbnail.jpegData(compressionQuality: 0.7)
    }

    func loadImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }

    func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size

        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        let aspectRatio = size.width / size.height
        var newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
