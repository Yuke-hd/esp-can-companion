import XCTest

final class AppSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    func testDriveStylePickerSyncsWithDriveAndSurvivesRelaunch() {
        launch()
        openSettings()
        choose("motorsport")
        capture("settings-motorsport")

        choose("cluster")
        XCTAssertTrue(styleOption("cluster").isSelected)
        capture("settings-cluster")

        // The top level shows the chosen style next to its category.
        goBack(until: driveRow)
        XCTAssertTrue(driveRow.label.contains("Cluster"), "the Drive row should show the chosen style, got \(driveRow.label)")
        capture("settings-root")

        // Drive shows the style picked in settings.
        leaveSettings()
        let exit = app.descendants(matching: .any)["drive.exit"]
        app.buttons["Drive"].tap(until: exit, timeout: 10)
        let cluster = app.descendants(matching: .any)["drive.cluster"]
        XCTAssertTrue(cluster.waitForExistence(timeout: 10), "Drive should show the Cluster style chosen in settings")

        // The Drive cycle button changes what settings shows.
        app.descendants(matching: .any)["drive.style"].tap(until: cluster, appearing: false)
        exit.tap(until: exit, appearing: false, timeout: 3)
        XCTAssertTrue(app.buttons["Pit Wall"].waitForExistence(timeout: 10))
        app.buttons["Pit Wall"].tap()
        openSettings()
        XCTAssertTrue(styleOption("motorsport").isSelected, "settings should follow the Drive cycle button")

        // The choice survives relaunch.
        choose("cluster")
        app.terminate()
        // No reset here, so the saved choice is what the relaunch reads. (Today
        // `-ResetAppConfig` clears only the app config, not `drive.style`.)
        launch(resetConfig: false)
        openSettings()
        XCTAssertTrue(styleOption("cluster").isSelected, "Drive style should survive relaunch")

        // Leave the default for other tests.
        choose("motorsport")
    }

    private func launch(resetConfig: Bool = true) {
        var arguments = [
            "-FakeController", "YES",
            "-DemoScenario", "connected"
        ]
        if resetConfig {
            arguments += ["-ResetAppConfig", "YES"]
        }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["Drive"].waitForExistence(timeout: 15))
    }

    private var driveRow: XCUIElement { app.buttons["settings.drive"] }

    /// Opens settings and its Drive page, where the style picker lives.
    private func openSettings() {
        let button = app.buttons["settings.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(button.label, "App settings")
        button.tap(until: driveRow, timeout: 5)
        driveRow.tap(until: styleOption("motorsport"), timeout: 5)
    }

    /// Back from the settings top level to the Pit Wall.
    private func leaveSettings() {
        goBack(until: app.buttons["settings.open"])
    }

    private func goBack(until element: XCUIElement) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap(until: element, timeout: 5)
    }

    private func styleOption(_ style: String) -> XCUIElement {
        app.buttons["settings.driveStyle.\(style)"]
    }

    private func choose(_ style: String) {
        let option = styleOption(style)
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let selected = NSPredicate(format: "isSelected == true")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: option)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(style) was not selected")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
