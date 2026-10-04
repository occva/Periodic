import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageAssetValidationError: Error {
    case invalidImage
    case unsupportedImageType
    case imageTooLarge
}

enum ImageAssetFormat: String, Hashable, Sendable {
    case png
    case jpeg

    var filenameExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

enum ImageAssetValidator {
    static let maximumImageSize = 10 * 1_024 * 1_024
    private static let maximumPixelCount = 32_000_000

    static func validate(_ data: Data) throws -> ImageAssetFormat {
        guard data.count <= maximumImageSize else {
            throw ImageAssetValidationError.imageTooLarge
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageAssetValidationError.invalidImage
        }
        guard let typeIdentifier = CGImageSourceGetType(source) as String? else {
            throw ImageAssetValidationError.unsupportedImageType
        }
        let format: ImageAssetFormat
        switch typeIdentifier {
        case UTType.png.identifier: format = .png
        case UTType.jpeg.identifier: format = .jpeg
        default: throw ImageAssetValidationError.unsupportedImageType
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              width <= maximumPixelCount / height else {
            throw ImageAssetValidationError.imageTooLarge
        }
        guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ImageAssetValidationError.invalidImage
        }
        return format
    }
}
