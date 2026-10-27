import XCTest

final class GaugesSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    func testRedlineEditReachesDriveRejectsInvalidInputAndSurvivesRelaunch() {
        launch(resetConfig: true)
        openSettings()
        // Drive's Motorsport style shows the shift lights this test reads.
        driveRow.tap(until: app.buttons["settings.driveStyle.motorsport"], timeout: 5)
        app.buttons["settings.driveStyle.motorsport"].tap()
        goBack(until: gaugesRow)
        XCTAssertTrue(gaugesRow.label.contains("Redline 6000"), "got \(gaugesRow.label)")
        gaugesRow.tap(until: redlineField, timeout: 5)

        // Above the fill end: an inline error, and the live band stays.
        replaceText(in: redlineField, with: "7000")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("at or below fill end"), "got \(error.label)")
        capture("gauges-invalid")

        replaceText(in: redlineField, with: "4000")
        XCTAssertTrue(error.waitForNonExistence(timeout: 5), "a valid band clears the error")
        redlineField.typeText("\n")
        capture("gauges-valid")
        goBack(until: gaugesRow)
        XCTAssertTrue(gaugesRow.label.contains("Redline 4000"), "got \(gaugesRow.label)")

        // Drive draws against the new redline without a reconnect: 4000 of a
        // 0–6500 fill puts red from the tenth of 15 lights (default: 14th).
        goBack(until: app.buttons["settings.open"])
        let exit = app.descendants(matching: .any)["drive.exit"]
        app.buttons["Drive"].tap(until: exit, timeout: 10)
        let lights = app.descendants(matching: .any)["drive.shift-lights"]
        XCTAssertTrue(lights.waitForExistence(timeout: 10))
        XCTAssertTrue(lights.label.contains("red from light 10"), "got \(lights.label)")

        // The band is saved: a relaunch without a reset still shows it.
        app.terminate()
        launch(resetConfig: false)
        openSettings()
        XCTAssertTrue(gaugesRow.label.contains("Redline 4000"), "after relaunch, got \(gaugesRow.label)")
    }

    private var driveRow: XCUIElement { app.buttons["settings.drive"] }
    private var gaugesRow: XCUIElement { app.buttons["settings.gauges"] }
    private var redlineField: XCUIElement { app.textFields["settings.rpm.redline"] }
    private var error: XCUIElement { app.descendants(matching: .any)["settings.rpm.error"] }

    private func launch(resetConfig: Bool) {
        var arguments = ["-FakeController", "YES", "-DemoScenario", "driveLaps"]
        if resetConfig { arguments += ["-ResetAppConfig", "YES"] }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["Drive"].waitForExistence(timeout: 15))
    }

    private func openSettings() {
        let button = app.buttons["settings.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap(until: gaugesRow, timeout: 5)
    }

    private func goBack(until element: XCUIElement) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap(until: element, timeout: 5)
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
