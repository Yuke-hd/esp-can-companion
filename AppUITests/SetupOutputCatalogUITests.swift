import XCTest

final class SetupOutputCatalogUITests: XCTestCase {
    func testCatalogFieldsAndZoneSettingLimitAppearInSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["-FakeController", "YES", "-DemoScenario", "connected"]
        app.launch()

        let setup = app.buttons["Setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 20))
        setup.tap()
        let preset = app.buttons["setup.preset.early-shift"]
        XCTAssertTrue(preset.waitForExistence(timeout: 20))
        preset.tap()

        let pixelCount = app.textFields["setup.sink.local_argb.pixel_count"]
        XCTAssertTrue(pixelCount.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "setup.catalog.led_effect.0.effect").firstMatch.exists)
        XCTAssertTrue(app.textFields["setup.catalog.led_fill.4.zone.start"].exists)
        XCTAssertTrue(app.textFields["setup.catalog.led_fill.4.color.red"].exists)

        app.buttons["setup.output.add.led_transient"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "setup.catalog.led_transient.7.duration_ms").firstMatch.waitForExistence(timeout: 5))

        pixelCount.tap()
        pixelCount.doubleTap()
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "50")
        XCTAssertTrue(app.staticTexts["setup.catalog.led_fill.4.zone.warning"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setup.send"].isEnabled, "Zone limit feedback must not replace controller-side upload validation")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "setup-output-catalog-editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
