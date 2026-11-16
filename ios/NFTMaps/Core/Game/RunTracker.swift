import AVFoundation
import CoreLocation
import CoreMotion
import Foundation
import Observation

enum RunGoal: Hashable, Sendable {
    case meters(Int)
    case steps(Int)

    var value: Int {
        switch self {
        case .meters(let value), .steps(let value): value
        }
    }

    var label: String {
        switch self {
        case .meters(let value): GameRules.number(value) + " m"
        case .steps(let value): GameRules.number(value) + " bước"
        }
    }
}

/// Theo dõi một vòng chạy: GPS (quãng đường + vết), CMPedometer (bước), đồng hồ có tạm dừng, thử thách, đọc mốc.
@MainActor
@Observable
final class RunTracker {
    enum Phase {
        case running
        case paused
        case finished
    }

    let goal: RunGoal
    let doubleXP: Bool
    private(set) var phase: Phase = .running
    private(set) var meters = 0.0
    private(set) var steps = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var route: [CLLocationCoordinate2D] = []
    private(set) var lastLocation: CLLocation?
    private(set) var challenge: RunChallenge?
    /// Sự kiện thử thách gần nhất (để UI hiện banner ngắn).
    private(set) var lastEvent: RunChallengeEngine.Event?
    /// Tăng mỗi khi có sự kiện, để UI bắt được cả khi sự kiện lặp lại giống hệt lần trước.
    private(set) var eventSerial = 0
    private(set) var petsMet = 0
    var voiceEnabled = true

    private var engine: RunChallengeEngine
    private var gpsMeters = 0.0
    private var goodFixes = 0
    private var pedometerSteps = 0
    private var pedometerMeters = 0.0
    private var excludedSteps = 0
    private var excludedMeters = 0.0
    private var stepsAtPause = 0
    private var metersAtPause = 0.0
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var nextVoiceKm = 1
    private var locationTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private let pedometer = CMPedometer()
    private let voice = AVSpeechSynthesizer()

    init(goal: RunGoal, sprint: Bool, hold: Bool, doubleXP: Bool) {
        self.goal = goal
        self.doubleXP = doubleXP
        engine = RunChallengeEngine(sprintEnabled: sprint, holdEnabled: hold)
    }

    // MARK: Chỉ số

    var secondsPerKm: Double? { meters > 50 ? elapsed / meters * 1000 : nil }

    var goalProgress: Double {
        switch goal {
        case .meters(let target): min(meters / Double(target), 1)
        case .steps(let target): min(Double(steps) / Double(target), 1)
        }
    }

    var remainingText: String {
        switch goal {
        case .meters(let target): GameRules.metersText(max(Double(target) - meters, 0))
        case .steps(let target): GameRules.number(max(target - steps, 0)) + " bước"
        }
    }

    var combo: Double { GameRules.comboMultiplier(petsMet: petsMet) }
    var completedChallenges: [RunChallenge.Kind] { engine.completed }

    var xp: Int {
        GameRules.runXP(meters: meters, petsMet: petsMet, doubled: doubleXP)
            + engine.completed.reduce(0) { $0 + GameRules.challengeXP($1) }
    }

    // MARK: Điều khiển

    func start() {
        segmentStart = .now
        backgroundSession = CLBackgroundActivitySession()
        startLocation()
        startPedometer(from: .now)
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func pause() {
        guard phase == .running else { return }
        tick()
        accumulated = elapsed
        segmentStart = nil
        stepsAtPause = pedometerSteps
        metersAtPause = pedometerMeters
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        excludedSteps += pedometerSteps - stepsAtPause
        excludedMeters += pedometerMeters - metersAtPause
        lastLocation = nil  // không tính đoạn đi lúc tạm dừng
        segmentStart = .now
        phase = .running
    }

    func petMet() {
        petsMet += 1
    }

    /// Kết thúc và trả về bản ghi. Vết chạy được cắt 200 m hai đầu và quy về hình 256×256, không giữ toạ độ thật.
    func finish() -> RunRecord {
        if phase == .running { tick() }
        phase = .finished
        locationTask?.cancel()
        tickTask?.cancel()
        pedometer.stopUpdates()
        backgroundSession?.invalidate()
        backgroundSession = nil

        var shape: Data?
        var area: RunArea?
        if meters >= LocationPrivacy.minimumRunMetersToMint, let trimmed = LocationPrivacy.trimmed(route) {
            shape = LocationPrivacy.shape(of: trimmed)
            area = LocationPrivacy.area(trimmed[trimmed.count / 2])
        }
        return RunRecord(date: .now, meters: meters, steps: steps, duration: elapsed, petsMet: petsMet,
                         completedChallenges: engine.completed, xp: xp, shape: shape, area: area)
    }

    func cancel() {
        locationTask?.cancel()
        tickTask?.cancel()
        pedometer.stopUpdates()
        backgroundSession?.invalidate()
    }

    // MARK: Cảm biến

    private func startLocation() {
        locationTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    if let location = update.location { self.apply(location) }
                }
            } catch {}
        }
    }

    private func apply(_ location: CLLocation) {
        guard phase == .running else { return }
        // Bỏ điểm sai số lớn; GPS trong hẻm/cao ốc ở VN hay nhảy.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30 else { return }
        if let previous = lastLocation {
            let step = location.distance(from: previous)
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            // Nhảy > 12 m/s là GPS lỗi, không phải người chạy.
            guard step >= 3, seconds > 0, step / seconds < 12 else { return }
            gpsMeters += step
        }
        goodFixes += 1
        lastLocation = location
        route.append(location.coordinate)
    }

    private func startPedometer(from start: Date) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let data else { return }
            let steps = data.numberOfSteps.intValue
            let meters = data.distance?.doubleValue ?? 0
            Task { @MainActor in
                self?.pedometerSteps = steps
                self?.pedometerMeters = meters
            }
        }
    }

    private func tick() {
        guard phase == .running else { return }
        elapsed = accumulated + (segmentStart.map { Date.now.timeIntervalSince($0) } ?? 0)
        let pedometerDistance = max(pedometerMeters - excludedMeters, 0)
        // Có GPS ổn định thì dùng GPS; trong nhà/không có fix thì dùng ước lượng của CMPedometer.
        meters = goodFixes >= 5 ? gpsMeters : max(gpsMeters, pedometerDistance)
        steps = CMPedometer.isStepCountingAvailable()
            ? max(pedometerSteps - excludedSteps, 0)
            : GameRules.estimatedSteps(meters: meters)

        for event in engine.update(meters: meters, elapsed: elapsed) {
            lastEvent = event
            eventSerial += 1
            switch event {
            case .started(let kind): say(kind == .sprint ? "Bứt tốc! 200 mét trong 60 giây." : "Giữ nhịp 500 mét.")
            case .completed: say("Hoàn thành thử thách!")
            case .failed: break
            }
            Haptics.notify(event.isFailure ? .warning : .success)
        }
        challenge = engine.active

        if meters >= Double(nextVoiceKm) * 1000 {
            let pace = GameRules.paceText(secondsPerKm: secondsPerKm)
                .replacingOccurrences(of: "'", with: " phút ").replacingOccurrences(of: "\"", with: " giây")
            say("\(nextVoiceKm) ki lô mét. Nhịp \(pace).")
            nextVoiceKm += 1
        }
    }

    private func say(_ text: String) {
        guard voiceEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        voice.speak(utterance)
    }
}

extension RunChallengeEngine.Event {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}
