import CoreLocation
import Foundation

/// Luật game thuần (không UI, không lưu trữ) để test được.
enum GameRules {
    // MARK: Cấp độ

    /// Tổng XP cần để lên cấp `level`: 0, 100, 300, 600, 1000…
    static func xpRequired(forLevel level: Int) -> Int {
        50 * level * (level - 1)
    }

    static func level(forXP xp: Int) -> Int {
        var level = 1
        while xpRequired(forLevel: level + 1) <= xp { level += 1 }
        return level
    }

    /// Tiến độ trong cấp hiện tại, 0...1.
    static func levelProgress(xp: Int) -> Double {
        let level = level(forXP: xp)
        let floor = xpRequired(forLevel: level)
        let ceiling = xpRequired(forLevel: level + 1)
        return Double(xp - floor) / Double(ceiling - floor)
    }

    // MARK: Thưởng

    /// 10 XP mỗi 100 m, cộng combo theo số bé gặp trong vòng (mỗi bé +0.25, tối đa x2). Vé x2 nhân đôi.
    static func runXP(meters: Double, petsMet: Int, doubled: Bool) -> Int {
        let base = Int(meters / 100) * 10
        let combo = min(1 + 0.25 * Double(petsMet), 2)
        return Int((Double(base) * combo).rounded()) * (doubled ? 2 : 1)
    }

    static func comboMultiplier(petsMet: Int) -> Double {
        min(1 + 0.25 * Double(petsMet), 2)
    }

    static let newPetXP = 50
    static let reencounterXP = 20
    static let levelUpCoins = 100
    static let medalXP = 150
    static let medalCoins = 50
    static let chestCoins = 120
    static let chestXP = 80
    static let checkInXP = 30
    static let checkInCoins = 10
    static let feedCost = 10
    static let feedXP = 5
    /// Mức bước trong ngày để nhận huy chương Vạn bước.
    static let tenKSteps = 10_000
    /// Một ngày tính vào chuỗi nếu chạy ít nhất chừng này.
    static let streakMinimumMeters = 1_000.0

    static func challengeXP(_ kind: RunChallenge.Kind) -> Int {
        switch kind {
        case .sprint: 40
        case .hold: 60
        }
    }

    // MARK: Độ hiếm khi khám phá

    /// Độ hiếm dựa trên việc bạn là người đầu tiên tìm ra khu đó, tính từ dữ liệu on-chain nên ai cũng kiểm chứng được:
    /// huyền thoại = chưa ai mint trong 1 km, sử thi = trong 300 m, hiếm = chưa có bé cùng loài trong 100 m.
    static func rarity(species: PetSpecies, at coordinate: CLLocationCoordinate2D,
                       among earlier: [MapToken]) -> Rarity {
        var nearest = Double.infinity
        var nearestSameSpecies = Double.infinity
        for token in earlier {
            let distance = LocationPrivacy.distance(coordinate, token.coordinate)
            nearest = min(nearest, distance)
            if token.species == species { nearestSameSpecies = min(nearestSameSpecies, distance) }
        }
        if nearest > 1_000 { return .legend }
        if nearest > 300 { return .epic }
        if nearestSameSpecies > 100 { return .rare }
        return .common
    }

    static func rarityBonusXP(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common: 0
        case .rare: 25
        case .epic: 60
        case .legend: 150
        }
    }

    // MARK: Chạy

    static func estimatedSteps(meters: Double) -> Int { Int(meters * 1.3) }

    /// ~1 kcal / kg / km với người 65 kg.
    static func kcal(meters: Double) -> Int { Int(meters * 0.065) }

    /// "6'13\"" cho tốc độ giây/km.
    static func paceText(secondsPerKm: Double?) -> String {
        guard let pace = secondsPerKm, pace.isFinite, pace > 0, pace < 3_600 else { return "–'––\"" }
        let total = Int(pace.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }

    static func metersText(_ meters: Double) -> String {
        Int(meters).formatted(.number.locale(Locale(identifier: "vi_VN"))) + " m"
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "vi_VN")))
    }
}

enum Rarity: Int, Codable, Comparable, CaseIterable, Sendable {
    case common, rare, epic, legend

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .common: "PHỔ THÔNG"
        case .rare: "HIẾM"
        case .epic: "SỬ THI"
        case .legend: "HUYỀN THOẠI"
        }
    }

    var stars: Int { rawValue + 1 }
}

/// Nhiệm vụ trong ngày — làm đủ 4 thì mở rương.
enum DailyQuest: String, CaseIterable, Codable, Identifiable, Sendable {
    case steps, run, meetPets, visitStation

    var id: Self { self }

    var title: String {
        switch self {
        case .steps: "\(GameRules.number(goal)) bước"
        case .run: "Chạy \(GameRules.number(goal)) m"
        case .meetPets: "Gặp \(goal) bé"
        case .visitStation: "Ghé trạm đối tác"
        }
    }

    var goal: Int {
        switch self {
        case .steps: 5_000
        case .run: 3_000
        case .meetPets: 2
        case .visitStation: 1
        }
    }

    var rewardXP: Int {
        switch self {
        case .steps: 40
        case .run: 60
        case .meetPets: 50
        case .visitStation: 30
        }
    }

    var rewardCoins: Int { 20 }

    var symbol: String {
        switch self {
        case .steps: "shoeprints.fill"
        case .run: "figure.run"
        case .meetPets: "pawprint.fill"
        case .visitStation: "heart.fill"
        }
    }
}

enum Medal: String, CaseIterable, Codable, Identifiable, Sendable {
    case sprint, hold, tenK

    var id: Self { self }

    var title: String {
        switch self {
        case .sprint: "Bứt tốc"
        case .hold: "Giữ nhịp"
        case .tenK: "Vạn bước"
        }
    }

    var detail: String {
        switch self {
        case .sprint: "200 m trong 60 giây"
        case .hold: "Giữ nhịp 500 m"
        case .tenK: "10.000 bước một ngày"
        }
    }

    var symbol: String {
        switch self {
        case .sprint: "bolt.fill"
        case .hold: "metronome.fill"
        case .tenK: "shoeprints.fill"
        }
    }
}
