import CoreLocation
import XCTest
@testable import NFTMaps

final class LocationPrivacyTests: XCTestCase {
    func testFuzzStaysWithinCellAndHidesExactPoint() {
        let point = CLLocationCoordinate2D(latitude: 10.776889, longitude: 106.700806)
        let fuzzed = LocationPrivacy.fuzz(point)
        let offset = LocationPrivacy.distance(point, fuzzed)
        XCTAssertLessThanOrEqual(offset, 72, "lệch tối đa nửa đường chéo ô 100 m")
        XCTAssertNotEqual(fuzzed.latitude, point.latitude)
        // Điểm khác trong cùng ô ra đúng cùng một tâm → mint nhiều lần không lộ dần vị trí thật.
        let nearby = CLLocationCoordinate2D(latitude: point.latitude + 0.00001, longitude: point.longitude + 0.00001)
        XCTAssertEqual(LocationPrivacy.fuzz(nearby).latitude, fuzzed.latitude, accuracy: 1e-12)
        XCTAssertEqual(LocationPrivacy.fuzz(nearby).longitude, fuzzed.longitude, accuracy: 1e-12)
        // Làm mờ lần nữa không đổi.
        XCTAssertEqual(LocationPrivacy.fuzz(fuzzed).latitude, fuzzed.latitude, accuracy: 1e-12)
    }

    func testFuzzWorksAcrossHemispheres() {
        for point in [CLLocationCoordinate2D(latitude: -33.856784, longitude: 151.215297),
                      CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)] {
            XCTAssertLessThanOrEqual(LocationPrivacy.distance(point, LocationPrivacy.fuzz(point)), 72)
        }
    }

    func testAreaRoundsToHundredths() {
        let area = LocationPrivacy.area(CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009))
        XCTAssertEqual(area, RunArea(lat: 1078, lng: 10670))
        XCTAssertEqual(LocationPrivacy.area(CLLocationCoordinate2D(latitude: -33.86, longitude: -70.6)),
                       RunArea(lat: -3386, lng: -7060))
    }

    /// Đường thẳng 1 km về phía bắc, mỗi 10 m một điểm.
    private var straightRoute: [CLLocationCoordinate2D] {
        (0...100).map { CLLocationCoordinate2D(latitude: 10.77 + Double($0) * 10 / 111_320, longitude: 106.70) }
    }

    func testTrimDropsTwoHundredMetersAtEachEnd() throws {
        let trimmed = try XCTUnwrap(LocationPrivacy.trimmed(straightRoute))
        let first = try XCTUnwrap(straightRoute.first), last = try XCTUnwrap(straightRoute.last)
        XCTAssertGreaterThanOrEqual(LocationPrivacy.distance(first, trimmed[0]), 199)
        XCTAssertGreaterThanOrEqual(LocationPrivacy.distance(last, trimmed[trimmed.count - 1]), 199)
        XCTAssertNil(LocationPrivacy.trimmed(Array(straightRoute.prefix(30))), "300 m thì cắt xong không còn gì")
    }

    func testShapeFitsGridWithoutCoordinates() throws {
        let square = [(0.0, 0.0), (0.0, 0.005), (0.005, 0.005), (0.005, 0.0), (0.0, 0.0)]
            .map { CLLocationCoordinate2D(latitude: 10.77 + $0.0, longitude: 106.70 + $0.1) }
        let shape = try XCTUnwrap(LocationPrivacy.shape(of: square))
        XCTAssertEqual(shape.count % 2, 0)
        XCTAssertTrue(shape.allSatisfy { (16...240).contains($0) }, "nằm trong lề 16 để nét vẽ không bị cắt")
        // Bắt đầu ở góc nam-tây → x nhỏ, y lớn (y hướng xuống như SVG).
        XCTAssertLessThan(shape[0], 30)
        XCTAssertGreaterThan(shape[1], 220)
    }

    func testShapeDownsamplesToContractLimit() throws {
        let long = (0..<5_000).map {
            CLLocationCoordinate2D(latitude: 10.77 + sin(Double($0) / 300) * 0.01, longitude: 106.70 + Double($0) * 0.00001)
        }
        let shape = try XCTUnwrap(LocationPrivacy.shape(of: long))
        XCTAssertLessThanOrEqual(shape.count, 2_000)
    }
}

final class GameRulesTests: XCTestCase {
    func testLevelCurve() {
        XCTAssertEqual(GameRules.level(forXP: 0), 1)
        XCTAssertEqual(GameRules.level(forXP: 99), 1)
        XCTAssertEqual(GameRules.level(forXP: 100), 2)
        XCTAssertEqual(GameRules.level(forXP: 7_800), 13)
        XCTAssertEqual(GameRules.levelProgress(xp: 200), 0.5, accuracy: 1e-9)
    }

    func testRunXPCombosAndTicket() {
        XCTAssertEqual(GameRules.runXP(meters: 3_210, petsMet: 0, doubled: false), 320)
        XCTAssertEqual(GameRules.runXP(meters: 3_210, petsMet: 2, doubled: false), 480)
        XCTAssertEqual(GameRules.runXP(meters: 3_210, petsMet: 10, doubled: true), 1_280, "combo tối đa x2, vé x2")
    }

    func testDiscoveryRarity() {
        let here = CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
        func token(_ id: UInt64, _ species: PetSpecies, metersNorth: Double) -> MapToken {
            let point = here.offset(meters: metersNorth, bearing: 0)
            return MapToken(id: id, owner: try! Address("0x0000000000000000000000000000000000000001"),
                            latitude: point.latitude, longitude: point.longitude, species: species, confidence: 90, name: "x")
        }
        XCTAssertEqual(GameRules.rarity(species: .cat, at: here, among: []), .legend)
        XCTAssertEqual(GameRules.rarity(species: .cat, at: here, among: [token(1, .cat, metersNorth: 600)]), .epic)
        XCTAssertEqual(GameRules.rarity(species: .cat, at: here, among: [token(1, .dog, metersNorth: 50)]), .rare)
        XCTAssertEqual(GameRules.rarity(species: .cat, at: here, among: [token(1, .cat, metersNorth: 50)]), .common)
    }

    func testPaceAndDurationText() {
        XCTAssertEqual(GameRules.paceText(secondsPerKm: 373), "6'13\"")
        XCTAssertEqual(GameRules.paceText(secondsPerKm: nil), "–'––\"")
        XCTAssertEqual(GameRules.durationText(1_192), "19:52")
        XCTAssertEqual(GameRules.durationText(3_725), "1:02:05")
    }
}

final class RunChallengeTests: XCTestCase {
    func testSprintCompletesWithinSixtySeconds() {
        var engine = RunChallengeEngine(sprintEnabled: true, holdEnabled: false)
        XCTAssertEqual(engine.update(meters: 499, elapsed: 170), [])
        XCTAssertEqual(engine.update(meters: 500, elapsed: 171), [.started(.sprint)])
        XCTAssertEqual(engine.active?.kind, .sprint)
        XCTAssertEqual(engine.update(meters: 650, elapsed: 200), [])
        XCTAssertEqual(engine.update(meters: 700, elapsed: 220), [.completed(.sprint)])
        XCTAssertEqual(engine.completed, [.sprint])
        XCTAssertNil(engine.active)
    }

    func testSprintFailsAfterDeadlineAndNextOneComesAKilometerLater() {
        var engine = RunChallengeEngine(sprintEnabled: true, holdEnabled: false)
        _ = engine.update(meters: 500, elapsed: 170)
        XCTAssertEqual(engine.update(meters: 650, elapsed: 231), [.failed(.sprint)])
        XCTAssertEqual(engine.update(meters: 1_499, elapsed: 500), [])
        XCTAssertEqual(engine.update(meters: 1_500, elapsed: 501), [.started(.sprint)])
    }

    func testHoldUsesAveragePaceWithFivePercentSlack() throws {
        var engine = RunChallengeEngine(sprintEnabled: false, holdEnabled: true)
        // 1.000 m trong 360 s → nhịp 0.36 s/m → được 500 × 0.36 × 1.05 = 189 s.
        XCTAssertEqual(engine.update(meters: 1_000, elapsed: 360), [.started(.hold)])
        let hold = try XCTUnwrap(engine.active)
        XCTAssertEqual(hold.timeLimit, 189, accuracy: 0.001)
        XCTAssertEqual(engine.update(meters: 1_500, elapsed: 540), [.completed(.hold)])
    }

    func testDisabledChallengesNeverStart() {
        var engine = RunChallengeEngine(sprintEnabled: false, holdEnabled: false)
        XCTAssertEqual(engine.update(meters: 5_000, elapsed: 1_800), [])
    }
}

@MainActor
final class GameStoreTests: XCTestCase {
    private func makeStore() -> GameStore {
        GameStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "game-\(UUID().uuidString).json"))
    }

    func testRunUnlocksMedalsAndLevelsUp() {
        let store = makeStore()
        store.recordRun(RunRecord(date: .now, meters: 3_210, steps: 4_173, duration: 1_192, petsMet: 1,
                                  completedChallenges: [.sprint, .hold], xp: 500))
        XCTAssertNotNil(store.progress.medals[.sprint])
        XCTAssertNotNil(store.progress.medals[.hold])
        XCTAssertEqual(store.progress.xp, 500 + 2 * GameRules.medalXP)
        XCTAssertEqual(store.level, GameRules.level(forXP: 800))
        XCTAssertTrue(store.rewards.contains(.medal(.sprint)))
        XCTAssertTrue(store.rewards.contains(.levelUp(2)))
        XCTAssertEqual(store.questProgress(.run), 3_210)
        XCTAssertEqual(store.streak, 1)
    }

    func testQuestsThenChest() {
        let store = makeStore()
        store.recordRun(RunRecord(date: .now, meters: 4_000, steps: 5_200, duration: 1_500, petsMet: 0,
                                  completedChallenges: [], xp: 0))
        store.recordNewPet(tokenID: 1, rarity: .common)
        store.recordReencounter(tokenID: 1)
        store.checkIn(StationDirectory.all.first { $0.kind == .partner }!)
        XCTAssertFalse(store.canOpenChest)
        DailyQuest.allCases.forEach(store.claimQuest)
        XCTAssertTrue(store.canOpenChest)
        let coins = store.progress.coins
        let levelBefore = store.level
        store.openChest()
        XCTAssertFalse(store.canOpenChest)
        // Rương cho 120 xu; 80 XP của rương có thể làm lên cấp (+100 xu mỗi cấp).
        XCTAssertEqual(store.progress.coins,
                       coins + GameRules.chestCoins + GameRules.levelUpCoins * (store.level - levelBefore))
        XCTAssertTrue(store.rewards.contains { if case .chest = $0 { true } else { false } })
        XCTAssertEqual(store.progress.x2Tickets, 2)
        XCTAssertEqual(store.friendship(of: 1), 2)
    }

    func testProgressPersists() {
        let url = FileManager.default.temporaryDirectory.appending(path: "game-\(UUID().uuidString).json")
        let store = GameStore(fileURL: url)
        store.addCoins(42)
        XCTAssertEqual(GameStore(fileURL: url).progress.coins, 42)
    }

    func testStreakCountsBackFromYesterday() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let days = Set((1...3).map { GameStore.dayKey(calendar.date(byAdding: .day, value: -$0, to: today)!, calendar: calendar) })
        XCTAssertEqual(GameStore.streak(days: days, today: today, calendar: calendar), 3)
        XCTAssertEqual(GameStore.streak(days: [], today: today, calendar: calendar), 0)
    }
}

final class ChainEncodingTests: XCTestCase {
    func testMintRunCalldataMatchesCast() throws {
        let run = RunRecord(date: .now, meters: 3_210, steps: 4_173, duration: 1_192, petsMet: 0, completedChallenges: [],
                            xp: 0, shape: try Data(hex: "0x0010203040506070"), area: RunArea(lat: 1078, lng: 10670))
        let call = try XCTUnwrap(RunNFTCall.mintRun(run, name: "Vòng Tao Đàn"))
        // cast calldata "mintRun(uint32,uint32,uint32,int16,int16,string,bytes)" 3210 4173 1192 1078 10670 "Vòng Tao Đàn" 0x0010203040506070
        XCTAssertEqual(call.hex, "0x704fee820000000000000000000000000000000000000000000000000000000000000c8a000000000000000000000000000000000000000000000000000000000000104d00000000000000000000000000000000000000000000000000000000000004a8000000000000000000000000000000000000000000000000000000000000043600000000000000000000000000000000000000000000000000000000000029ae00000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000000f56c3b26e672054616f20c490c3a06e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080010203040506070000000000000000000000000000000000000000000000000")
    }

    func testNegativeAreaEncodesAndDecodes() throws {
        let encoded = ABI.encode([.int(-3386)])
        XCTAssertEqual(try ABIDecoder(data: encoded).int64(at: 0), -3386)
        XCTAssertEqual(Int16(truncatingIfNeeded: try ABIDecoder(data: encoded).int64(at: 0)), -3386)
    }

    func testGooglePolylineDecode() {
        // Ví dụ trong tài liệu Google Encoded Polyline.
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 1e-9)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 1e-9)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 1e-9)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 1e-9)
    }

    func testShortPlaceNamePrefersWard() {
        // Dạng trả về thật của NullMaps /geocode/json?latlng=10.7769,106.7009.
        let json: [String: Any] = ["status": "OK", "results": [[
            "formatted_address": "86 Lê Thánh Tôn, Phường Sài Gòn, Quận 1, Thành phố Hồ Chí Minh",
            "address_components": [
                ["long_name": "86", "types": ["street_number"]],
                ["long_name": "Lê Thánh Tôn", "types": ["route"]],
                ["long_name": "Phường Sài Gòn", "types": ["sublocality", "sublocality_level_1", "political"]],
                ["long_name": "Quận 1", "types": ["administrative_area_level_2", "political"]],
                ["long_name": "Thành phố Hồ Chí Minh", "types": ["administrative_area_level_1", "locality", "political"]],
            ],
        ]]]
        XCTAssertEqual(NullMapsClient.shortPlaceName(json), "Phường Sài Gòn")
        XCTAssertNil(NullMapsClient.shortPlaceName(["status": "ZERO_RESULTS", "results": []]))
    }
}
