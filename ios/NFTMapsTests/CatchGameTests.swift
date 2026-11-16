import CoreGraphics
import XCTest
@testable import NFTMaps

final class CatchGameTests: XCTestCase {
    func testTargetMapsVisionBoxToScreen() {
        // Ảnh dọc 1000×2000 trên màn 400×800: aspect fill đúng tỉ lệ, không cắt.
        let detection = PetDetection(species: .cat, confidence: 0.8,
                                     boundingBox: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25))
        let target = CatchTarget(detection, imageSize: CGSize(width: 1000, height: 2000),
                                 in: CGSize(width: 400, height: 800))
        XCTAssertEqual(target.center.x, 200, accuracy: 0.001)
        XCTAssertEqual(target.center.y, 300, accuracy: 0.001)  // Vision gốc dưới-trái → màn hình gốc trên-trái
        XCTAssertEqual(target.radius, 84, accuracy: 0.001)
        XCTAssertEqual(target.confidence, 80)
    }

    func testTargetUsesOnlyVisiblePartOfCroppedImage() {
        // Ảnh ngang 2000×1000 lấp màn dọc 400×800 → hai mép bị cắt; khung con vật phủ cả ảnh.
        let detection = PetDetection(species: .dog, confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))
        let target = CatchTarget(detection, imageSize: CGSize(width: 2000, height: 1000),
                                 in: CGSize(width: 400, height: 800))
        XCTAssertEqual(target.center.x, 200, accuracy: 0.001)
        XCTAssertEqual(target.center.y, 400, accuracy: 0.001)
        XCTAssertEqual(target.radius, 130, accuracy: 0.001)  // kẹp ở bán kính tối đa
    }

    func testThrowQualityByDistance() {
        XCTAssertEqual(ThrowQuality(distance: 0, radius: 100), .bullseye)
        XCTAssertEqual(ThrowQuality(distance: 50, radius: 100), .great)
        XCTAssertEqual(ThrowQuality(distance: 95, radius: 100), .hit)
        XCTAssertEqual(ThrowQuality(distance: 100, radius: 100), .hit)
        XCTAssertNil(ThrowQuality(distance: 101, radius: 100))
        XCTAssertEqual(ThrowQuality.bullseye.catchChance, 1)
    }

    func testFlightArcStartsAndEndsOnPoints() {
        let flight = Flight(rest: CGPoint(x: 200, y: 700), start: CGPoint(x: 210, y: 680),
                            end: CGPoint(x: 150, y: 300), apex: 100)
        XCTAssertEqual(flight.point(at: 0), flight.start)
        XCTAssertEqual(flight.point(at: 1), flight.end)
        // Đường bay cong lên trên đoạn thẳng nối hai đầu…
        XCTAssertLessThan(flight.point(at: 0.5).y, (flight.start.y + flight.end.y) / 2)
        // …và có lúc lên cao hơn điểm rơi rồi mới rơi xuống (kiểu ném bổng).
        let highest = stride(from: 0.0, through: 1.0, by: 0.01).map { flight.point(at: $0).y }.min()!
        XCTAssertLessThan(highest, flight.end.y)
    }

    func testCropRectCentersOnPet() {
        // Ảnh 1000×800, con vật 200×200 ở (100, 200) theo gốc trên-trái.
        let focus = CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.25)
        XCTAssertEqual(PetPhoto.cropRect(width: 1000, height: 800, focus: focus), CGRect(x: 0, y: 100, width: 400, height: 400))
        XCTAssertEqual(PetPhoto.cropRect(width: 1000, height: 800, focus: nil), CGRect(x: 100, y: 0, width: 800, height: 800))
    }

    func testThumbnailFitsOnChainLimitEvenForNoise() throws {
        // Nhiễu ngẫu nhiên là trường hợp JPEG nén tệ nhất.
        let side = 1200
        var generator = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in pixels.indices { pixels[index] = UInt8.random(in: 0...255, using: &generator) }
        let image = try XCTUnwrap(pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        })
        let thumbnail = try XCTUnwrap(PetPhoto.thumbnail(of: image, focus: nil))
        XCTAssertLessThanOrEqual(thumbnail.count, PetPhoto.maxBytes)
        XCTAssertEqual(Array(thumbnail.prefix(2)), [0xff, 0xd8])  // JPEG
    }
}
