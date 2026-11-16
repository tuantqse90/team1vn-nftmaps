import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Chuẩn bị ảnh: đọc + xoay đúng chiều cho model, rồi cắt thành JPEG vuông nhỏ để lưu on-chain.
enum PetPhoto {
    /// Trần dung lượng JPEG on-chain (contract cho tối đa 24 000 byte). ~12 KB ≈ 2.7M gas trên Fuji.
    static let maxBytes = 12_000

    /// Đọc ảnh (JPEG/HEIC/PNG…), áp hướng EXIF và thu nhỏ cạnh dài về `maxPixelSize`.
    static func uprightImage(from data: Data, maxPixelSize: Int = 1600) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// JPEG vuông ≤ `maxBytes`, căn vào con vật nếu có `focus`. Ảnh được vẽ lại nên không mang EXIF/GPS gốc.
    static func thumbnail(of image: CGImage, focus: CGRect?) -> Data? {
        guard let cropped = image.cropping(to: cropRect(width: image.width, height: image.height, focus: focus)) else {
            return nil
        }
        // Ảnh thường dừng ở 256px; ảnh nhiều chi tiết (lá cây, sỏi…) lùi dần cho tới khi vừa trần byte.
        for side in [256, 224, 192, 160, 128, 96] {
            guard let resized = resize(cropped, side: side) else { return nil }
            for quality in [0.7, 0.6, 0.5, 0.4, 0.3] {
                if let jpeg = encodeJPEG(resized, quality: quality), jpeg.count <= maxBytes {
                    return jpeg
                }
            }
        }
        return nil
    }

    /// Hình vuông quanh con vật (cạnh = 1.3 × cạnh dài của khung, ít nhất nửa cạnh ngắn của ảnh), kẹp trong ảnh.
    /// Không có `focus` thì lấy hình vuông giữa ảnh. Kết quả theo pixel, gốc trên-trái.
    static func cropRect(width: Int, height: Int, focus: CGRect?) -> CGRect {
        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        let shortSide = min(imageWidth, imageHeight)

        guard let focus else {
            return CGRect(x: (imageWidth - shortSide) / 2, y: (imageHeight - shortSide) / 2,
                          width: shortSide, height: shortSide).integral
        }
        // Vision: chuẩn hoá 0...1, gốc dưới-trái → pixel, gốc trên-trái.
        let box = CGRect(x: focus.minX * imageWidth, y: (1 - focus.maxY) * imageHeight,
                         width: focus.width * imageWidth, height: focus.height * imageHeight)
        let side = min(shortSide, max(max(box.width, box.height) * 1.3, shortSide / 2))
        let x = min(max(box.midX - side / 2, 0), imageWidth - side)
        let y = min(max(box.midY - side / 2, 0), imageHeight - side)
        return CGRect(x: x, y: y, width: side, height: side).integral
    }

    private static func resize(_ image: CGImage, side: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
