import Foundation
import UIKit

/// 图片读取：解码 → 等比缩到长边 2048 → JPEG 0.8。
enum ImageLoader {
    static let maxImages = 4
    static let maxDimension: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.8

    enum LoadError: LocalizedError {
        case invalidImage
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage: "这张图片读不出来。"
            case .encodeFailed: "图片压缩失败。"
            }
        }
    }

    static func load(data: Data) throws -> PendingAttachment {
        guard let image = UIImage(data: data) else { throw LoadError.invalidImage }
        let resized = downscale(image, maxDimension: maxDimension)
        guard let jpeg = resized.jpegData(compressionQuality: jpegQuality) else {
            throw LoadError.encodeFailed
        }
        return .image(data: jpeg, mimeType: "image/jpeg")
    }

    static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxDimension else { return image }
        let scale = maxDimension / longSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
