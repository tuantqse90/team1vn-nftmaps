import CoreMotion
import Foundation
import Observation

/// Một vòng chạy đã xong, lưu trên máy. `shape` + `area` đủ để mint vòng chạy sau này.
struct RunRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var meters: Double
    var steps: Int
    var duration: TimeInterval
    var petsMet: Int
    var completedChallenges: [RunChallenge.Kind]
    var xp: Int
    var shape: Data?
    var area: RunArea?
    var mintedTokenID: UInt64?

    var secondsPerKm: Double? { meters > 50 ? duration / meters * 1000 : nil }
    var canMint: Bool { shape != nil && area != nil && mintedTokenID == nil }
}

/// Bé bắt được lúc mất mạng (hoặc mint lỗi): giữ lại trên máy, có mạng thì mint tiếp.
struct PendingMint: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var species: UInt8
    var confidence: UInt8
    /// Đã làm mờ (hoặc không, tuỳ cài đặt lúc bắt).
    var latitude: Double
    var longitude: Double
    var photo: Data
    var createdAt = Date()
}

/// Phần thưởng chờ hiện màn ăn mừng.
enum RewardEvent: Identifiable, Equatable, Sendable {
    case levelUp(Int)
    case medal(Medal)
    case chest(coins: Int, xp: Int, tickets: Int)

    var id: String {
        switch self {
        case .levelUp(let level): "level-\(level)"
        case .medal(let medal): "medal-\(medal.rawValue)"
        case .chest: "chest"
        }
    }
}

struct GameProgress: Codable, Sendable {
    var xp = 0
    var coins = 0
    var x2Tickets = 1
    var day = ""
    var dayMeters = 0.0
    var dayRunSteps = 0
    var dayPetsMet = 0
    var dayStationVisited = false
    var claimedQuests: Set<DailyQuest> = []
    var chestOpened = false
    var runDays: Set<String> = []
    var medals: [Medal: Date] = [:]
    var runs: [RunRecord] = []
    /// token id → số lần gặp (độ thân thiết).
    var encounters: [UInt64: Int] = [:]
    /// trạm → ngày check-in gần nhất.
    var checkIns: [String: String] = [:]
    var feedings: [String: Int] = [:]
    var following: [String] = []
    var pendingMints: [PendingMint] = []
}

/// Tiến trình game của một ví, lưu JSON trên máy. Không có server nên mỗi máy giữ tiến trình riêng.
@MainActor
@Observable
final class GameStore {
    private(set) var progress: GameProgress
    /// Bước chân cả ngày hôm nay từ CMPedometer (kể cả lúc không mở app).
    private(set) var todaySteps = 0
    var rewards: [RewardEvent] = []

    private let fileURL: URL?
    private let pedometer = CMPedometer()

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(GameProgress.self, from: data) {
            progress = saved
        } else {
            progress = GameProgress()
        }
        rolloverIfNeeded()
    }

    convenience init(owner: Address) {
        let folder = URL.applicationSupportDirectory.appending(path: "PawRun", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.init(fileURL: folder.appending(path: "game-\(owner.hex.lowercased()).json"))
    }

    // MARK: Chỉ số

    var level: Int { GameRules.level(forXP: progress.xp) }
    var levelProgress: Double { GameRules.levelProgress(xp: progress.xp) }
    var xpToNextLevel: Int { GameRules.xpRequired(forLevel: level + 1) - progress.xp }
    var stepsToday: Int { max(todaySteps, progress.dayRunSteps) }
    var totalRunMeters: Double { progress.runs.reduce(0) { $0 + $1.meters } }

    func friendship(of tokenID: UInt64) -> Int { progress.encounters[tokenID] ?? 0 }

    // MARK: Ngày mới

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func rolloverIfNeeded(now: Date = .now) {
        let today = Self.dayKey(now)
        guard progress.day != today else { return }
        progress.day = today
        progress.dayMeters = 0
        progress.dayRunSteps = 0
        progress.dayPetsMet = 0
        progress.dayStationVisited = false
        progress.claimedQuests = []
        progress.chestOpened = false
        todaySteps = 0
        save()
    }

    /// Đọc bước chân từ nửa đêm tới giờ. Máy không có cảm biến (Simulator) thì giữ số bước từ các vòng chạy.
    func refreshSteps() async {
        rolloverIfNeeded()
        guard CMPedometer.isStepCountingAvailable() else { return }
        let start = Calendar.current.startOfDay(for: .now)
        let steps: Int? = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: .now) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
        if let steps {
            todaySteps = steps
            if steps >= GameRules.tenKSteps { unlock(.tenK) }
        }
    }

    // MARK: Ghi nhận

    func addXP(_ amount: Int) {
        guard amount > 0 else { return }
        let before = level
        progress.xp += amount
        let after = level
        if after > before {
            for reached in (before + 1)...after {
                progress.coins += GameRules.levelUpCoins
                rewards.append(.levelUp(reached))
            }
        }
        save()
    }

    func recordRun(_ run: RunRecord) {
        rolloverIfNeeded()
        progress.runs.append(run)
        progress.dayMeters += run.meters
        progress.dayRunSteps += run.steps
        if run.meters >= GameRules.streakMinimumMeters {
            progress.runDays.insert(Self.dayKey(run.date))
        }
        for kind in Set(run.completedChallenges) {
            unlock(kind == .sprint ? .sprint : .hold)
        }
        if stepsToday >= GameRules.tenKSteps { unlock(.tenK) }
        addXP(run.xp)
    }

    func markRunMinted(_ runID: UUID, tokenID: UInt64) {
        guard let index = progress.runs.firstIndex(where: { $0.id == runID }) else { return }
        progress.runs[index].mintedTokenID = tokenID
        save()
    }

    /// Bé mới vừa mint (hoặc đang chờ mint).
    func recordNewPet(tokenID: UInt64?, rarity: Rarity) {
        rolloverIfNeeded()
        progress.dayPetsMet += 1
        if let tokenID { progress.encounters[tokenID] = max(progress.encounters[tokenID] ?? 0, 1) }
        addXP(GameRules.newPetXP + GameRules.rarityBonusXP(rarity))
    }

    func recordReencounter(tokenID: UInt64) {
        rolloverIfNeeded()
        progress.dayPetsMet += 1
        progress.encounters[tokenID, default: 1] += 1
        addXP(GameRules.reencounterXP)
    }

    func addCoins(_ amount: Int) {
        progress.coins += amount
        save()
    }

    func useTicket() -> Bool {
        guard progress.x2Tickets > 0 else { return false }
        progress.x2Tickets -= 1
        save()
        return true
    }

    private func unlock(_ medal: Medal) {
        guard progress.medals[medal] == nil else { return }
        progress.medals[medal] = .now
        progress.coins += GameRules.medalCoins
        rewards.append(.medal(medal))
        addXP(GameRules.medalXP)
    }

    // MARK: Nhiệm vụ & rương

    func questProgress(_ quest: DailyQuest) -> Int {
        switch quest {
        case .steps: stepsToday
        case .run: Int(progress.dayMeters)
        case .meetPets: progress.dayPetsMet
        case .visitStation: progress.dayStationVisited ? 1 : 0
        }
    }

    func isQuestDone(_ quest: DailyQuest) -> Bool { questProgress(quest) >= quest.goal }
    func isQuestClaimed(_ quest: DailyQuest) -> Bool { progress.claimedQuests.contains(quest) }

    func claimQuest(_ quest: DailyQuest) {
        guard isQuestDone(quest), !isQuestClaimed(quest) else { return }
        progress.claimedQuests.insert(quest)
        progress.coins += quest.rewardCoins
        addXP(quest.rewardXP)
    }

    var claimedCount: Int { progress.claimedQuests.count }
    var canOpenChest: Bool { claimedCount == DailyQuest.allCases.count && !progress.chestOpened }

    func openChest() {
        guard canOpenChest else { return }
        progress.chestOpened = true
        progress.coins += GameRules.chestCoins
        progress.x2Tickets += 1
        rewards.append(.chest(coins: GameRules.chestCoins, xp: GameRules.chestXP, tickets: 1))
        addXP(GameRules.chestXP)
    }

    // MARK: Chuỗi ngày

    /// Số ngày chạy liên tiếp tính tới hôm nay (hoặc hôm qua nếu hôm nay chưa chạy).
    static func streak(days: Set<String>, today: Date, calendar: Calendar = .current) -> Int {
        var day = today
        if !days.contains(dayKey(day, calendar: calendar)) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(dayKey(day, calendar: calendar)) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    var streak: Int { Self.streak(days: progress.runDays, today: .now) }

    /// 7 ngày của tuần này (T2…CN): đã chạy chưa, có phải hôm nay không.
    var week: [(label: String, done: Bool, isToday: Bool)] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let labels = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday)!
            return (labels[offset], progress.runDays.contains(Self.dayKey(date)), calendar.isDate(date, inSameDayAs: today))
        }
    }

    // MARK: Trạm

    func hasCheckedIn(_ station: Station) -> Bool {
        progress.checkIns[station.id] == Self.dayKey(.now)
    }

    func checkIn(_ station: Station) {
        rolloverIfNeeded()
        guard !hasCheckedIn(station) else { return }
        progress.checkIns[station.id] = Self.dayKey(.now)
        if station.kind == .partner { progress.dayStationVisited = true }
        progress.coins += GameRules.checkInCoins
        addXP(GameRules.checkInXP)
    }

    func feedings(at station: Station) -> Int { progress.feedings[station.id] ?? 0 }

    /// Góp 1 bữa bằng coin. false nếu không đủ coin.
    func feed(at station: Station) -> Bool {
        guard progress.coins >= GameRules.feedCost else { return false }
        progress.coins -= GameRules.feedCost
        progress.feedings[station.id, default: 0] += 1
        addXP(GameRules.feedXP)
        return true
    }

    // MARK: Bạn bè

    func isFollowing(_ address: Address) -> Bool {
        progress.following.contains(address.hex.lowercased())
    }

    func follow(_ address: Address) {
        guard !isFollowing(address) else { return }
        progress.following.append(address.hex.lowercased())
        save()
    }

    func unfollow(_ address: Address) {
        progress.following.removeAll { $0 == address.hex.lowercased() }
        save()
    }

    var followedAddresses: [Address] { progress.following.compactMap { try? Address($0) } }

    // MARK: Chờ mint

    func enqueue(_ pending: PendingMint) {
        progress.pendingMints.append(pending)
        save()
    }

    func removePending(_ id: UUID) {
        progress.pendingMints.removeAll { $0.id == id }
        save()
    }

    // MARK: Lưu

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
