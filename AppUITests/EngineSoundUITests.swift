import XCTest

final class EngineSoundUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    func testSoundAndDuckingSurviveRelaunch() {
        launch()
        openDrive()
        openSettings()
        setSwitch("engineSound.enabled", to: false)
        setSwitch("engineSound.lowersOtherAudio", to: true)
        setSwitch("engineSound.enabled", to: true)
        setSwitch("engineSound.lowersOtherAudio", to: false)
        app.buttons["engineSound.done"].tap()
        XCTAssertEqual(app.buttons["drive.sound"].value as? String, "On")
        app.terminate()

        // Keep the app's saved data and identical scenario arguments. No
        // preference launch arguments may override the persisted values.
        launch()
        openDrive()
        openSettings()
        assertSwitchValue(app.switches["engineSound.enabled"], isEnabled: true)
        reveal(app.switches["engineSound.lowersOtherAudio"])
        assertSwitchValue(app.switches["engineSound.lowersOtherAudio"], isEnabled: false)
        capture("engine-sound-persisted-after-relaunch")
        setSwitch("engineSound.enabled", to: false)
        setSwitch("engineSound.lowersOtherAudio", to: true)
        app.buttons["engineSound.done"].tap()
        XCTAssertEqual(app.buttons["drive.sound"].value as? String, "Off")
    }

    func testSettingsInBothStylesAtLargestText() {
        launch(largeText: true)
        openDrive()
        let cluster = app.descendants(matching: .any)["drive.cluster"]
        if cluster.exists { app.buttons["drive.style"].tap(until: cluster, appearing: false) }
        inspectSettings(style: "motorsport")
        app.buttons["drive.style"].tap(until: cluster)
        XCTAssertTrue(cluster.waitForExistence(timeout: 5))
        inspectSettings(style: "cluster")
    }

    private func inspectSettings(style: String) {
        let sound = app.buttons["drive.sound"]
        XCTAssertEqual(sound.label, "Engine sound settings")
        XCTAssertTrue(["On", "Off"].contains(sound.value as? String ?? ""))
        capture("engine-sound-\(style)-control-largest-text")
        openSettings()
        XCTAssertTrue(app.switches["engineSound.enabled"].exists)
        XCTAssertEqual(app.switches["engineSound.enabled"].label, "Engine sound")
        capture("engine-sound-\(style)-settings-top-largest-text")
        let engine = app.descendants(matching: .any)["engineSound.engine"]
        reveal(engine)
        XCTAssertTrue((engine.label + " " + (engine.value as? String ?? "")).contains("LS V8"))
        let ducking = app.switches["engineSound.lowersOtherAudio"]
        reveal(ducking)
        XCTAssertEqual(ducking.label, "Lower other audio while playing")
        let windowFrame = app.windows.element(boundBy: 0).frame
        XCTAssertTrue(windowFrame.contains(ducking.frame), "Ducking control \(ducking.frame) is outside window \(windowFrame)")
        XCTAssertTrue(app.buttons["engineSound.done"].isHittable)
        capture("engine-sound-\(style)-settings-scrolled-largest-text")
        app.buttons["engineSound.done"].tap()
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
    }

    private func launch(largeText: Bool = false) {
        app.launchArguments = ["-FakeController", "YES", "-DemoScenario", "driveLaps"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["Drive"].waitForExistence(timeout: 20))
    }

    private func openDrive() {
        let exit = app.buttons["drive.exit"]
        app.buttons["Drive"].tap(until: exit, timeout: 15)
        XCTAssertTrue(exit.waitForExistence(timeout: 10))
        // Match the existing Drive capture workflow: a requested window
        // geometry alone does not rotate the Simulator's screen capture.
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in
            let frame = self.app.windows.element(boundBy: 0).frame
            return frame.width > frame.height
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: nil)], timeout: 10), .completed)
    }

    private func openSettings() {
        app.buttons["drive.sound"].tap(until: app.switches["engineSound.enabled"], timeout: 10)
        XCTAssertTrue(app.switches["engineSound.enabled"].waitForExistence(timeout: 5))
    }

    private func setSwitch(_ identifier: String, to enabled: Bool) {
        let control = app.switches[identifier]
        reveal(control)
        if (control.value as? String == "1") != enabled {
            // SwiftUI exposes the whole Form row as the switch; tap its trailing thumb.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        assertSwitchValue(control, isEnabled: enabled)
    }

    private func assertSwitchValue(_ control: XCUIElement, isEnabled enabled: Bool) {
        let expected = enabled ? "1" : "0"
        let updated = NSPredicate { _, _ in control.value as? String == expected }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated, object: nil)], timeout: 10), .completed,
                       "Switch did not reach \(expected); actual value: \(control.value ?? "nil")")
        XCTAssertEqual(control.value as? String, expected)
    }

    private func reveal(_ element: XCUIElement) {
        func fullyVisible() -> Bool {
            element.isHittable && app.windows.element(boundBy: 0).frame.contains(element.frame)
        }
        let form = app.descendants(matching: .any)["engineSound.form"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if fullyVisible() { return }
            form.swipeUp()
        }
        for _ in 0..<4 {
            if fullyVisible() { return }
            form.swipeDown()
        }
        if !fullyVisible() { capture("engine-sound-settings-reveal-failure") }
        XCTAssertTrue(fullyVisible(),
                      "Settings control must be fully visible and reachable by scrolling; control=\(element.frame), form=\(form.frame), window=\(app.windows.element(boundBy: 0).frame)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
