import XCTest

/// Đi một vòng qua các màn chính và lưu ảnh chụp màn hình (để xem giao diện, không kiểm tra logic).
/// Ảnh lưu vào thư mục `SHOTS_DIR` (truyền bằng `TEST_RUNNER_SHOTS_DIR=… xcodebuild test`).
final class TourUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotsDir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory())
    }

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testTour() throws {
        if app.textFields["username"].waitForExistence(timeout: 5) {
            shot("00-login")
            app.textFields["username"].tap()
            app.textFields["username"].typeText("pawrun-demo")
            app.secureTextFields["password"].tap()
            app.secureTextFields["password"].typeText("demo-pass-123")
            app.buttons["signIn"].tap()
        }
        dismissSavePassword()

        if app.buttons["permissionsDone"].waitForExistence(timeout: 30) {
            shot("01-permissions")
            app.buttons["permissionsDone"].tap()
        }

        XCTAssertTrue(app.buttons["startRun"].waitForExistence(timeout: 20))
        sleep(6)
        shot("02-map")

        dismissSavePassword()
        let stations = ["Cà phê Hẻm 12", "Điểm cho ăn Tao Đàn", "Tiệm bánh Meo Meo"].map { app.buttons[$0].firstMatch }
        if let station = stations.first(where: { $0.exists && $0.isHittable }) {
            station.tap()
            sleep(2)
            shot("03-map-station-card")
            let close = app.buttons.matching(NSPredicate(format: "label == 'Đóng'")).firstMatch
            if close.exists { close.tap() }
        }

        app.buttons["Nhiệm vụ"].tap()
        sleep(1)
        shot("04-quests")
        app.buttons["Thử thách"].tap()
        sleep(1)
        shot("05-challenges")

        app.buttons["Sưu tập"].tap()
        sleep(2)
        shot("06-collection")

        app.buttons["Hồ sơ"].tap()
        sleep(1)
        shot("07-profile")

        app.buttons["startRun"].tap()
        XCTAssertTrue(app.buttons["beginRun"].waitForExistence(timeout: 5))
        sleep(4)
        shot("08-run-setup")
        app.buttons["beginRun"].tap()
        sleep(6)
        shot("09-running")
        app.buttons["finishRun"].tap()
        let end = app.buttons["Kết thúc"]
        if end.waitForExistence(timeout: 3) { end.tap() }
        XCTAssertTrue(app.staticTexts["Xong vòng!"].waitForExistence(timeout: 5) || app.buttons["claimReward"].exists)
        sleep(1)
        shot("10-summary")
        if app.buttons["claimReward"].waitForExistence(timeout: 2) {
            shot("11-reward")
        }
    }

    /// Hộp thoại "Lưu mật khẩu?" của iOS hiện sau khi đăng nhập.
    private func dismissSavePassword() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for button in [app.buttons["Not Now"], springboard.buttons["Not Now"], app.buttons["Lúc khác"]] {
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: shotsDir.appending(path: "\(name).png"))
    }
}
