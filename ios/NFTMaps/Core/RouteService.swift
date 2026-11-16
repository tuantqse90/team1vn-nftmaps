import CoreLocation
import Foundation
import MapKit
import OSLog

/// Một tuyến đi bộ/chạy: các điểm trên đường thật + tổng quãng đường.
struct RoutePlan: Sendable, Equatable {
    let coordinates: [CLLocationCoordinate2D]
    let meters: Double
    let seconds: Double

    static func == (lhs: RoutePlan, rhs: RoutePlan) -> Bool {
        lhs.meters == rhs.meters && lhs.coordinates.count == rhs.coordinates.count
    }

    static func + (lhs: RoutePlan, rhs: RoutePlan) -> RoutePlan {
        RoutePlan(coordinates: lhs.coordinates + rhs.coordinates.dropFirst(),
                  meters: lhs.meters + rhs.meters, seconds: lhs.seconds + rhs.seconds)
    }
}

/// Client NullMaps (API kiểu Google Maps của backend tự host). Cần `Config.nullMapsAPIKey`.
struct NullMapsClient: Sendable {
    let baseURL: URL
    let apiKey: String

    enum NullMapsError: LocalizedError {
        case status(String)

        var errorDescription: String? {
            switch self {
            case .status(let status): "NullMaps trả về \(status)"
            }
        }
    }

    func walkingRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> RoutePlan {
        let json = try await get("maps/api/directions/json", [
            "origin": "\(start.latitude),\(start.longitude)",
            "destination": "\(end.latitude),\(end.longitude)",
            "mode": "walking",
        ])
        guard let routes = json["routes"] as? [[String: Any]], let route = routes.first,
              let overview = route["overview_polyline"] as? [String: Any],
              let points = overview["points"] as? String,
              let legs = route["legs"] as? [[String: Any]]
        else { throw NullMapsError.status(json["status"] as? String ?? "dữ liệu lạ") }
        let meters = legs.compactMap { ($0["distance"] as? [String: Any])?["value"] as? Double }.reduce(0, +)
        let seconds = legs.compactMap { ($0["duration"] as? [String: Any])?["value"] as? Double }.reduce(0, +)
        return RoutePlan(coordinates: Polyline.decode(points), meters: meters, seconds: seconds)
    }

    /// Tên khu vực ngắn gọn (phường/quận) cho một toạ độ.
    func placeName(_ coordinate: CLLocationCoordinate2D) async throws -> String? {
        let json = try await get("maps/api/geocode/json", ["latlng": "\(coordinate.latitude),\(coordinate.longitude)"])
        return Self.shortPlaceName(json)
    }

    /// Lấy phường, không có thì quận, rồi thành phố; cuối cùng mới dùng cả địa chỉ dài.
    static func shortPlaceName(_ json: [String: Any]) -> String? {
        guard let first = (json["results"] as? [[String: Any]])?.first else { return nil }
        let components = first["address_components"] as? [[String: Any]] ?? []
        for type in ["sublocality", "administrative_area_level_2", "locality"] {
            if let match = components.first(where: { ($0["types"] as? [String])?.contains(type) == true }),
               let name = match["long_name"] as? String {
                return name
            }
        }
        return first["formatted_address"] as? String
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw NullMapsError.status("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)") }
        if let status = json["status"] as? String, status != "OK" { throw NullMapsError.status(status) }
        return json
    }
}

/// Encoded polyline của Google (precision 5).
enum Polyline {
    static func decode(_ encoded: String, precision: Double = 1e5) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0, latitude = 0, longitude = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1f) << shift
                shift += 5
                if byte < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }
        while index < bytes.count, let dLat = next(), let dLng = next() {
            latitude += dLat
            longitude += dLng
            coordinates.append(CLLocationCoordinate2D(latitude: Double(latitude) / precision,
                                                      longitude: Double(longitude) / precision))
        }
        return coordinates
    }
}

/// Dẫn đường đi bộ: ưu tiên NullMaps (nếu có key), lỗi thì lùi về Apple MapKit.
@MainActor
enum RouteService {
    private static let log = Logger(subsystem: "com.hackbuilder.nftmaps", category: "route")

    static var nullMaps: NullMapsClient? {
        guard let url = Config.nullMapsURL, !Config.nullMapsAPIKey.isEmpty else { return nil }
        return NullMapsClient(baseURL: url, apiKey: Config.nullMapsAPIKey)
    }

    static func walkingRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> RoutePlan {
        if let nullMaps {
            do {
                let plan = try await nullMaps.walkingRoute(from: start, to: end)
                log.notice("NullMaps route \(Int(plan.meters)) m")
                return plan
            } catch {
                log.error("NullMaps route lỗi, dùng MapKit: \(error.localizedDescription, privacy: .public)")
            }
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .walking
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw URLError(.cannotFindHost) }
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount)
        route.polyline.getCoordinates(&points, range: NSRange(location: 0, length: route.polyline.pointCount))
        return RoutePlan(coordinates: points, meters: route.distance, seconds: route.expectedTravelTime)
    }

    /// Vòng chạy khép kín ~`targetMeters` theo hướng `bearing`: đi hai cạnh tam giác đều rồi về chỗ cũ, bám đường thật.
    static func loop(from start: CLLocationCoordinate2D, targetMeters: Double, bearing: Double) async throws -> RoutePlan {
        // Đường thật thường dài hơn đường chim bay ~25%.
        let side = targetMeters / 3 / 1.25
        let a = start.offset(meters: side, bearing: bearing)
        let b = start.offset(meters: side, bearing: bearing + 60)
        let first = try await walkingRoute(from: start, to: a)
        let second = try await walkingRoute(from: a, to: b)
        let third = try await walkingRoute(from: b, to: start)
        return first + second + third
    }

    static func placeName(_ coordinate: CLLocationCoordinate2D) async -> String? {
        if let nullMaps {
            do {
                if let name = try await nullMaps.placeName(coordinate) {
                    log.notice("NullMaps place \(name, privacy: .public)")
                    return name
                }
            } catch {
                log.error("NullMaps geocode lỗi, dùng CLGeocoder: \(error.localizedDescription, privacy: .public)")
            }
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            preferredLocale: Locale(identifier: "vi_VN")).first
        return placemark?.subAdministrativeArea ?? placemark?.subLocality ?? placemark?.locality
    }
}

extension CLLocationCoordinate2D {
    /// Điểm cách `meters` theo hướng `bearing` (độ, 0 = bắc).
    func offset(meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        let dLat = meters * cos(radians) / 111_320
        let dLng = meters * sin(radians) / (111_320 * cos(latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: latitude + dLat, longitude: longitude + dLng)
    }

    func distance(to other: CLLocationCoordinate2D) -> Double {
        LocationPrivacy.distance(self, other)
    }
}
