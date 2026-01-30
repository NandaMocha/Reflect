import Foundation
import UIKit

enum CompressionQuality {
    case low
    case medium
    case high

    var jpegQuality: CGFloat {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.8
        }
    }

    var maxDimension: CGFloat {
        switch self {
        case .low: return 800
        case .medium: return 1200
        case .high: return 1600
        }
    }
}

protocol ImageProcessingServiceProtocol {
    func compressImage(_ image: UIImage, quality: CompressionQuality) async -> Data?
    func generateThumbnail(_ image: UIImage, size: CGSize) async -> Data?
    func loadImage(from data: Data) -> UIImage?
    func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage?
}
