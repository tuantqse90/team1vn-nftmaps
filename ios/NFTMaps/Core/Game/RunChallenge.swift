import Foundation

/// Thử thách bật lên giữa vòng chạy. Cả hai đều là "chạy đủ X mét trước khi hết giờ":
/// - Bứt tốc: 200 m trong 60 giây, bật lên ở mét 500 rồi mỗi 1.000 m.
/// - Giữ nhịp: 500 m với nhịp không chậm hơn 5% so với nhịp trung bình lúc bắt đầu, bật lên ở mét 1.000 rồi mỗi 1.000 m.
struct RunChallenge: Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case sprint, hold

        var title: String {
            switch self {
            case .sprint: "Bứt tốc 200 m"
            case .hold: "Giữ nhịp 500 m"
            }
        }
    }

    let kind: Kind
    let startMeters: Double
    let startTime: TimeInterval
    let targetMeters: Double
    let timeLimit: TimeInterval

    func covered(at meters: Double) -> Double { max(meters - startMeters, 0) }
    func progress(at meters: Double) -> Double { min(covered(at: meters) / targetMeters, 1) }
    func secondsLeft(at elapsed: TimeInterval) -> TimeInterval { max(startTime + timeLimit - elapsed, 0) }
}

struct RunChallengeEngine: Sendable {
    enum Event: Equatable, Sendable {
        case started(RunChallenge.Kind)
        case completed(RunChallenge.Kind)
        case failed(RunChallenge.Kind)
    }

    static let sprintMeters = 200.0
    static let sprintSeconds = 60.0
    static let holdMeters = 500.0
    /// Nhịp tham chiếu bị kẹp trong 4'10"/km … 10'00"/km để người đi bộ hay chạy rất nhanh vẫn hợp lý.
    static let paceRange = 0.25...0.6

    let sprintEnabled: Bool
    let holdEnabled: Bool
    private(set) var active: RunChallenge?
    private(set) var completed: [RunChallenge.Kind] = []
    private var nextSprintAt = 500.0
    private var nextHoldAt = 1_000.0

    init(sprintEnabled: Bool, holdEnabled: Bool) {
        self.sprintEnabled = sprintEnabled
        self.holdEnabled = holdEnabled
    }

    /// Gọi đều đặn khi đang chạy (không gọi lúc tạm dừng).
    mutating func update(meters: Double, elapsed: TimeInterval) -> [Event] {
        var events: [Event] = []
        if let challenge = active {
            if challenge.covered(at: meters) >= challenge.targetMeters {
                completed.append(challenge.kind)
                events.append(.completed(challenge.kind))
                active = nil
            } else if challenge.secondsLeft(at: elapsed) <= 0 {
                events.append(.failed(challenge.kind))
                active = nil
            }
            if active != nil { return events }
        }

        if sprintEnabled, meters >= nextSprintAt {
            nextSprintAt = meters + 1_000
            active = RunChallenge(kind: .sprint, startMeters: meters, startTime: elapsed,
                                  targetMeters: Self.sprintMeters, timeLimit: Self.sprintSeconds)
            events.append(.started(.sprint))
        } else if holdEnabled, meters >= nextHoldAt {
            nextHoldAt = meters + 1_000
            let average = meters > 0 ? elapsed / meters : Self.paceRange.upperBound
            let pace = min(max(average, Self.paceRange.lowerBound), Self.paceRange.upperBound) * 1.05
            active = RunChallenge(kind: .hold, startMeters: meters, startTime: elapsed,
                                  targetMeters: Self.holdMeters, timeLimit: Self.holdMeters * pace)
            events.append(.started(.hold))
        }
        return events
    }
}
