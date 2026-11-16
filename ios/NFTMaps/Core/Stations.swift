import CoreLocation
import Foundation

/// Trạm đối tác (quán/cửa hàng thân thiện với chó mèo) và điểm cho ăn trên bản đồ.
struct Station: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case partner
        case feeding
    }

    let id: String
    let kind: Kind
    let name: String
    let latitude: Double
    let longitude: Double
    let hours: String?
    /// Số bữa cần góp để đầy mục tiêu tuần.
    let feedingGoal: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Phải đứng trong bán kính này mới check-in được.
    static let checkInRadius = 60.0
}

enum StationDirectory {
    /// ⚠️ DỮ LIỆU MẪU quanh công viên Tao Đàn (Q1, TP.HCM) để demo — thay bằng danh sách đối tác thật
    /// (ví dụ tải từ server hoặc từ `place/nearbysearch` của NullMaps sau khi đã ký hợp tác với quán).
    static let all: [Station] = [
        Station(id: "partner-hem12", kind: .partner, name: "Cà phê Hẻm 12",
                latitude: 10.77560, longitude: 106.69330, hours: "7:00–22:00", feedingGoal: 200),
        Station(id: "partner-meomeo", kind: .partner, name: "Tiệm bánh Meo Meo",
                latitude: 10.77905, longitude: 106.69640, hours: "8:00–21:00", feedingGoal: 150),
        Station(id: "feed-taodan", kind: .feeding, name: "Điểm cho ăn Tao Đàn",
                latitude: 10.77370, longitude: 106.69180, hours: nil, feedingGoal: 200),
        Station(id: "feed-bokè", kind: .feeding, name: "Điểm cho ăn bờ kè",
                latitude: 10.78890, longitude: 106.69460, hours: nil, feedingGoal: 120),
    ]
}
