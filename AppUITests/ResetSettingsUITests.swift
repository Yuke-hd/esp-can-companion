import XCTest

final class ResetSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    func testBrakeScaleEditAndResetRestoreAndPersistDefaults() {
        launch(resetConfig: true)
        openSettings()

        // Move every setting away from its default.
        driveRow.tap(until: app.buttons["settings.driveStyle.cluster"], timeout: 5)
        app.buttons["settings.driveStyle.cluster"].tap()
        goBack(until: gaugesRow)
        XCTAssertTrue(driveRow.label.contains("Cluster"), "got \(driveRow.label)")
        gaugesRow.tap(until: brakeField, timeout: 5)
        XCTAssertEqual(brakeField.value as? String, "70")

        // Out of range: an inline error; committing keeps the live scale.
        replaceText(in: brakeField, with: "500")
        XCTAssertTrue(brakeError.waitForExistence(timeout: 5))
        XCTAssertTrue(brakeError.label.contains("10 to 200 bar"), "got \(brakeError.label)")
        brakeField.typeText("\n")
        XCTAssertTrue(brakeError.exists, "the error stays after an invalid commit")
        capture("gauges-brake-invalid")
        goBack(until: gaugesRow)
        gaugesRow.tap(until: brakeField, timeout: 5)
        XCTAssertEqual(brakeField.value as? String, "70", "an invalid scale is never applied")

        replaceText(in: brakeField, with: "120")
        XCTAssertTrue(brakeError.waitForNonExistence(timeout: 5))
        brakeField.typeText("\n")
        replaceText(in: redlineField, with: "4000")
        redlineField.typeText("\n")
        capture("gauges-brake-valid")
        goBack(until: gaugesRow)
        XCTAssertTrue(gaugesRow.label.contains("Redline 4000"), "got \(gaugesRow.label)")
        gaugesRow.tap(until: brakeField, timeout: 5)
        XCTAssertEqual(brakeField.value as? String, "120")
        goBack(until: resetButton)

        // Cancelling the confirmation changes nothing.
        resetButton.tap(until: confirmReset, timeout: 5)
        capture("settings-reset-confirmation")
        dismissResetConfirmation()
        XCTAssertTrue(gaugesRow.label.contains("Redline 4000"), "got \(gaugesRow.label)")

        // Confirming restores every page.
        resetButton.tap(until: confirmReset, timeout: 5)
        confirmReset.tap(until: confirmReset, appearing: false)
        assertDefaultsShown()

        // The defaults are saved: a relaunch without a reset still shows them.
        app.terminate()
        launch(resetConfig: false)
        openSettings()
        assertDefaultsShown()
    }

    private func assertDefaultsShown(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(driveRow.label.contains("Motorsport"), "got \(driveRow.label)", file: file, line: line)
        XCTAssertTrue(gaugesRow.label.contains("Redline 6000"), "got \(gaugesRow.label)", file: file, line: line)
        driveRow.tap(until: app.buttons["settings.driveStyle.motorsport"], timeout: 5)
        XCTAssertTrue(app.buttons["settings.driveStyle.motorsport"].isSelected, file: file, line: line)
        goBack(until: gaugesRow)
        gaugesRow.tap(until: brakeField, timeout: 5)
        XCTAssertEqual(brakeField.value as? String, "70", file: file, line: line)
        XCTAssertEqual(redlineField.value as? String, "6000", file: file, line: line)
        XCTAssertEqual(app.textFields["settings.rpm.fillFrom"].value as? String, "0", file: file, line: line)
        XCTAssertEqual(app.textFields["settings.rpm.fillTo"].value as? String, "6500", file: file, line: line)
        goBack(until: resetButton)
    }

    private var driveRow: XCUIElement { app.buttons["settings.drive"] }
    private var gaugesRow: XCUIElement { app.buttons["settings.gauges"] }
    private var resetButton: XCUIElement { app.buttons["settings.reset"] }
    /// iOS 26 shows the dialog as a popover that lists the button twice, so take the first match.
    private var confirmReset: XCUIElement { app.buttons["settings.reset.confirm"].firstMatch }
    private var brakeField: XCUIElement { app.textFields["settings.brake.scale"] }
    private var redlineField: XCUIElement { app.textFields["settings.rpm.redline"] }
    private var brakeError: XCUIElement { app.descendants(matching: .any)["settings.brake.error"] }

    /// Before iOS 26 the dialog is an action sheet with Cancel. On iOS 26 it
    /// is a popover above the Reset row without one; the system's dismiss
    /// region covers the screen and is tapped at its centre, below the row.
    private func dismissResetConfirmation() {
        let cancel = app.buttons["Cancel"]
        let outside = app.otherElements["PopoverDismissRegion"]
        if cancel.exists {
            cancel.tap(until: confirmReset, appearing: false)
        } else {
            XCTAssertTrue(outside.exists, "expected Cancel or a popover dismiss region")
            outside.tap(until: confirmReset, appearing: false)
        }
    }

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
