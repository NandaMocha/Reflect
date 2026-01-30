import Foundation
import UIKit

class ImageProcessingService: ImageProcessingServiceProtocol {
    static let shared = ImageProcessingService()

    // MARK: - Thumbnail Caching

    private var thumbnailCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB
        return cache
    }()

    private init() {}

    // MARK: - Async Image Processing

    func compressImage(_ image: UIImage, quality: CompressionQuality) async -> Data? {
        // Perform image processing on background thread to avoid blocking UI
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return nil }
            let maxDimension = quality.maxDimension
            guard let resized = self.resizeImage(image, maxDimension: maxDimension) else {
                return image.jpegData(compressionQuality: quality.jpegQuality)
            }
            return resized.jpegData(compressionQuality: quality.jpegQuality)
        }.value
    }

    func generateThumbnail(_ image: UIImage, size: CGSize) async -> Data? {
        // Create cache key based on size and image hash
        let cacheKey = "\(Int(size.width))x\(Int(size.height))-\(image.hashValue)" as NSString

        // Check cache first
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached as Data
        }

        // Generate thumbnail on background thread
        let thumbnail = await Task.detached(priority: .userInitiated) {
            let aspectWidth = size.width / image.size.width
            let aspectHeight = size.height / image.size.height
            let aspectRatio = min(aspectWidth, aspectHeight)

            let scaledSize = CGSize(
                width: image.size.width * aspectRatio,
                height: image.size.height * aspectRatio
            )

            let renderer = UIGraphicsImageRenderer(size: scaledSize)
            let thumb = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: scaledSize))
            }

            return thumb.jpegData(compressionQuality: 0.7)
        }.value

        // Cache the result
        if let data = thumbnail {
            thumbnailCache.setObject(data as NSData, forKey: cacheKey)
        }

        return thumbnail
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
