import CoreLocation
import XCTest
@testable import NFTMaps

/// Gọi NullMaps chạy local thật. Tự bỏ qua nếu chưa cấu hình (thiếu Local.xcconfig).
@MainActor
final class NullMapsLiveTests: XCTestCase {
    func testWalkingRouteFromLocalNullMaps() async throws {
        guard let client = RouteService.nullMaps else { throw XCTSkip("Chưa cấu hình NullMaps") }
        print("NullMaps base:", client.baseURL.absoluteString)
        do {
            let plan = try await client.walkingRoute(
                from: CLLocationCoordinate2DMake(10.7752, 106.6929),
                to: CLLocationCoordinate2DMake(10.7769, 106.7009))
            print("NullMaps route:", plan.meters, plan.coordinates.count)
            XCTAssertGreaterThan(plan.meters, 500)
            let name = try await client.placeName(CLLocationCoordinate2DMake(10.7752, 106.6929))
            print("NullMaps place:", name ?? "nil")
            XCTAssertNotNil(name)
        } catch {
            throw XCTSkip("NullMaps không chạy: \(error)")
        }
    }
}
