import XCTest

final class DriveNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    func testDriveFromPitWallHidesTabBarAndExitsToPortrait() {
        launchConnected()
        openDrive()
        waitForLandscape()

        for title in ["Pit Wall", "Setup", "Strip", "Drive"] {
            XCTAssertFalse(app.buttons[title].exists, "tab bar should be hidden while Drive is visible")
        }
        captureLandscape("drive-landscape-pit-wall")

        exitDrive()
        waitForPortrait()
        XCTAssertTrue(app.buttons["Pit Wall"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Drive"].exists)
        capturePortrait("drive-exit-pit-wall-portrait")
    }

    func testDriveExitsToSetupAndCanBeReentered() {
        launchConnected()
        XCTAssertTrue(app.buttons["Setup"].waitForExistence(timeout: 10))
        app.buttons["Setup"].tap()
        XCTAssertTrue(app.buttons["Setup"].waitForExistence(timeout: 5))

        openDrive()
        waitForLandscape()
        exitDrive()
        waitForPortrait()
        XCTAssertTrue(app.buttons["Setup"].waitForExistence(timeout: 5))

        openDrive()
        waitForLandscape()
        captureLandscape("drive-reentered-landscape")
        exitDrive()
        waitForPortrait()
        XCTAssertTrue(app.buttons["Setup"].waitForExistence(timeout: 5))
    }

    func testDriveShowsNumericReadoutsAndUnsupportedSignalsAsInactive() {
        launchConnected()
        openDrive()
        waitForLandscape()

        assertText(for: "drive.gear", matchingAny: ["1", "2", "3", "4", "5", "6"])
        assertText(for: "drive.rpm", matchingAny: ["2", "3", "4", "5", "6"])
        assertText(for: "drive.speed", matchingAny: ["3", "5", "7", "9"])
        assertText(for: "drive.throttle", containing: "Not supported")
        assertText(for: "drive.gmeter", containing: "g accelerating")
        captureLandscape("drive-readouts-and-unsupported-signals")
    }

    func testDriveShowsUnknownValuesAfterStalledScenario() {
        launch(scenario: "stalled")
        openDrive()
        waitForLandscape()

        assertText(for: "drive.rpm", containing: "Unknown")
        assertText(for: "drive.speed", containing: "Unknown")
        assertText(for: "drive.gear", containing: "Unknown")
        captureLandscape("drive-stalled-unknown")
    }

    func testDriveShowsNotLinkedStateWithoutTelemetry() {
        launch(scenario: "notPaired")
        openDrive()
        waitForLandscape()

        assertText(for: "drive.link", containing: "not linked")
        assertText(for: "drive.rpm", containing: "Unknown")
        assertText(for: "drive.speed", containing: "Unknown")
        captureLandscape("drive-not-linked")
    }

    private func launchConnected() {
        launch(scenario: "connected")
    }

    private func launch(scenario: String) {
        app.launchArguments = [
            "-FakeController", "YES",
            "-DemoScenario", scenario
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Drive"].waitForExistence(timeout: 15))
    }

    private func openDrive() {
        app.buttons["Drive"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["drive.exit"].waitForExistence(timeout: 10))
    }

    private func exitDrive() {
        let exit = app.descendants(matching: .any)["drive.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
    }

    private func waitForLandscape() {
        waitForWindowOrientation { $0.width > $0.height }
    }

    private func waitForPortrait() {
        waitForWindowOrientation { $0.height > $0.width }
    }

    private func captureLandscape(_ name: String) {
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape()
        capture(name + "-layout-preflight")
        assertDriveContentIsVisible()
        capture(name)
    }

    private func capturePortrait(_ name: String) {
        XCUIDevice.shared.orientation = .portrait
        waitForPortrait()
        capture(name)
    }

    private func waitForWindowOrientation(
        _ condition: @escaping (CGRect) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate { _, _ in
            condition(self.app.windows.element(boundBy: 0).frame)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 15)
        XCTAssertEqual(result, XCTWaiter.Result.completed, "window did not reach the expected orientation", file: file, line: line)
    }

    private func assertDriveContentIsVisible(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.element(boundBy: 0)
        let windowFrame = window.frame
        let identifiers = [
            "drive.exit",
            "drive.shift-lights",
            "drive.turn.left",
            "drive.turn.right",
            "drive.gear",
            "drive.rpm",
            "drive.speed",
            "drive.brake",
            "drive.throttle",
            "drive.gmeter",
            "drive.link"
        ]

        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(identifier)", file: file, line: line)
            let frame = element.frame
            XCTAssertTrue(frame.width > 0 && frame.height > 0, "\(identifier) has no layout frame: \(frame)", file: file, line: line)
            XCTAssertTrue(windowFrame.contains(frame), "\(identifier) is clipped by window \(windowFrame): \(frame)", file: file, line: line)
        }

        let gaugeIdentifiers = ["drive.gear", "drive.brake", "drive.throttle", "drive.gmeter"]
        let gaugeFrames = Dictionary(uniqueKeysWithValues: gaugeIdentifiers.map {
            ($0, app.descendants(matching: .any)[$0].frame)
        })
        for (left, right) in [
            ("drive.gear", "drive.brake"),
            ("drive.gear", "drive.throttle"),
            ("drive.gear", "drive.gmeter"),
            ("drive.brake", "drive.throttle"),
            ("drive.throttle", "drive.gmeter")
        ] {
            XCTAssertFalse(
                gaugeFrames[left]!.intersects(gaugeFrames[right]!),
                "\(left) overlaps \(right): \(gaugeFrames[left]!) vs \(gaugeFrames[right]!)",
                file: file,
                line: line
            )
        }

        let exit = app.descendants(matching: .any)["drive.exit"]
        XCTAssertTrue(exit.isHittable, "drive.exit is not hittable at \(exit.frame)", file: file, line: line)
    }

    private func assertText(
        for identifier: String,
        containing text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(identifier)", file: file, line: line)
        waitForText(element, containing: text, file: file, line: line)
    }

    private func assertText(
        for identifier: String,
        matchingAny values: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(identifier)", file: file, line: line)
        let predicate = NSPredicate { _, _ in
            let summary = self.accessibilitySummary(of: element)
            return values.contains(where: summary.contains)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 15)
        XCTAssertEqual(result, XCTWaiter.Result.completed, "\(identifier) did not show a numeric value", file: file, line: line)
    }

    private func waitForText(
        _ element: XCUIElement,
        containing text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate { _, _ in
            self.accessibilitySummary(of: element).localizedCaseInsensitiveContains(text)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 15)
        XCTAssertEqual(result, XCTWaiter.Result.completed, "\(element.identifier) did not show \(text)", file: file, line: line)
    }

    private func accessibilitySummary(of element: XCUIElement) -> String {
        let value = (element.value as? String) ?? ""
        return "\(element.label) \(value)"
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
