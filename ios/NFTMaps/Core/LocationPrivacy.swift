import CoreLocation
import Foundation

/// Mọi toạ độ trước khi lên chain đều đi qua đây. Dữ liệu trên chain ai cũng đọc được và không xoá được.
enum LocationPrivacy {
    /// Cạnh ô lưới khi làm mờ: điểm thật bị kéo về tâm ô, lệch tối đa ~71 m (nửa đường chéo).
    static let cellMeters: Double = 100
    /// Bỏ đoạn đầu và cuối của vết chạy (thường là nhà mình) trước khi lưu hình vòng chạy.
    static let routeTrimMeters: Double = 200
    /// Vòng chạy ngắn hơn mức này thì cắt xong không còn gì đáng lưu.
    static let minimumRunMetersToMint: Double = 500

    private static let metersPerDegree = 111_320.0

    /// Kéo toạ độ về tâm ô lưới ~100 m. Dùng tâm ô cố định thay vì cộng nhiễu ngẫu nhiên:
    /// mint nhiều lần ở cùng chỗ thì nhiễu ngẫu nhiên sẽ trung bình về đúng điểm thật, còn tâm ô thì không.
    static func fuzz(_ coordinate: CLLocationCoordinate2D, cellMeters: Double = cellMeters) -> CLLocationCoordinate2D {
        let latStep = cellMeters / metersPerDegree
        let latitude = (floor(coordinate.latitude / latStep) + 0.5) * latStep
        // Bước kinh độ tính theo vĩ độ tâm hàng ô để mọi điểm trong cùng hàng dùng chung một lưới.
        let lngStep = cellMeters / (metersPerDegree * max(cos(latitude * .pi / 180), 0.01))
        let longitude = (floor(coordinate.longitude / lngStep) + 0.5) * lngStep
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Khu vực thô ~1 km cho bảng xếp hạng: độ × 100, làm tròn (10.7769 → 1078).
    static func area(_ coordinate: CLLocationCoordinate2D) -> RunArea {
        RunArea(lat: Int16((coordinate.latitude * 100).rounded()), lng: Int16((coordinate.longitude * 100).rounded()))
    }

    /// Bỏ `trimMeters` đầu và cuối của vết chạy. nil nếu phần còn lại quá ngắn để vẽ.
    static func trimmed(_ route: [CLLocationCoordinate2D], trimMeters: Double = routeTrimMeters) -> [CLLocationCoordinate2D]? {
        guard route.count >= 2 else { return nil }
        var cumulative = [0.0]
        for index in 1..<route.count {
            cumulative.append(cumulative[index - 1] + distance(route[index - 1], route[index]))
        }
        let total = cumulative.last ?? 0
        let kept = route.indices.filter { cumulative[$0] >= trimMeters && cumulative[$0] <= total - trimMeters }
        guard kept.count >= 2 else { return nil }
        return kept.map { route[$0] }
    }

    /// Hình vòng chạy (không kèm toạ độ thật): chiếu lên lưới 256×256, giữ tỉ lệ, chừa lề 16, y hướng xuống như SVG.
    /// Kết quả là các cặp byte (x, y) — đúng định dạng `route` của RunNFT, tối đa `maxPoints` điểm.
    static func shape(of route: [CLLocationCoordinate2D], maxPoints: Int = 1000) -> Data? {
        guard route.count >= 2, let origin = route.first else { return nil }
        let cosLat = cos(origin.latitude * .pi / 180)
        let projected = route.map { point in
            (x: (point.longitude - origin.longitude) * metersPerDegree * cosLat,
             y: (point.latitude - origin.latitude) * metersPerDegree)
        }
        let minX = projected.map(\.x).min()!, maxX = projected.map(\.x).max()!
        let minY = projected.map(\.y).min()!, maxY = projected.map(\.y).max()!
        let span = max(maxX - minX, maxY - minY, 1)
        let scale = (255.0 - 32) / span
        let offsetX = 16 + ((255.0 - 32) - (maxX - minX) * scale) / 2
        let offsetY = 16 + ((255.0 - 32) - (maxY - minY) * scale) / 2

        var points: [(UInt8, UInt8)] = []
        for point in projected {
            let x = UInt8(clamping: Int(((point.x - minX) * scale + offsetX).rounded()))
            let y = UInt8(clamping: Int((255 - ((point.y - minY) * scale + offsetY)).rounded()))
            if let last = points.last, last == (x, y) { continue }
            points.append((x, y))
        }
        if points.count > maxPoints {
            let stride = Double(points.count - 1) / Double(maxPoints - 1)
            points = (0..<maxPoints).map { points[Int((Double($0) * stride).rounded())] }
        }
        guard points.count >= 2 else { return nil }
        return Data(points.flatMap { [$0.0, $0.1] })
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

/// Khu vực ~1 km lưu kèm vòng chạy trên chain.
struct RunArea: Codable, Hashable, Sendable {
    let lat: Int16
    let lng: Int16
}
