import XCTest

final class DiscoveredSignalsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    func testNewSignalChoiceMetadataAndSheetNavigation() {
        open("discoveredSignals")
        assertRow("example.enabled", contains: ["True", "Fresh", "Unit: none", "Catalog evidence: reference"])
        assertRow("example.mode", contains: ["new_choice", "Unverified", "Choices: idle, new_choice"])
        XCTAssertLessThan(row("example.enabled").frame.minY, row("example.mode").frame.minY,
                          "semantic-key row order must match the accessibility reading order")
        capture("discovered-new-choice")
        reveal("example.signed")
        assertRow("example.signed", contains: ["-1.25", "Fresh", "Unit: m/s^2"])
        if row("example.peer").exists {
            XCTAssertLessThan(row("example.peer").frame.minY, row("example.signed").frame.minY)
        }
        capture("discovered-signed-number")
        closeSheet()
        XCTAssertTrue(app.buttons["signals.open"].waitForExistence(timeout: 5))
        app.buttons["signals.open"].tap()
        assertRow("example.mode", contains: ["new_choice"])
        capture("discovered-reopened")
    }

    func testPartialRecordsExpireIndependentlyWhilePeerIsFresh() {
        open("discoveredPartial")
        assertRow("example.enabled", contains: ["True", "Fresh"])
        assertRow("example.peer", contains: ["Fresh"])
        capture("partial-valid")
        assertRow("example.enabled", contains: ["no value", "Unknown"], timeout: 20)
        assertRow("example.peer", contains: ["Fresh"])
        assertState("Discovered signals")
        capture("partial-independent-expiration")
    }

    func testStreamStallsAfterValidValues() {
        open("discoveredStalled")
        assertRow("example.enabled", contains: ["True", "Fresh"])
        capture("stall-valid")
        assertState("Telemetry stalled", timeout: 20)
        assertRow("example.enabled", contains: ["no value", "Unknown"])
        capture("stall-cleared")
    }

    func testMalformedValidPrefixDoesNotKeepValuesLive() {
        open("discoveredMalformed")
        assertRow("example.enabled", contains: ["True", "Fresh"])
        capture("malformed-before")
        assertState("Telemetry stalled", timeout: 20)
        assertRow("example.enabled", contains: ["no value", "Unknown"])
        assertRow("example.peer", contains: ["no value", "Unknown"])
        capture("malformed-cleared")
    }

    func testSameTokenReconnectRemapsHandlesAndChoices() {
        open("discoveredReconnect")
        assertRow("example.enabled", contains: ["True", "Fresh"])
        assertRow("example.mode", contains: ["new_choice", "Choices: idle, new_choice"])
        capture("remap-before")
        let cleared = NSPredicate { _, _ in
            !self.row("example.enabled").exists || self.row("example.enabled").label.contains("Unknown")
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: nil)], timeout: 20), .completed)
        capture("remap-disconnected-cleared")
        openSheet()
        assertRow("example.enabled", contains: ["False", "Fresh"], timeout: 35)
        assertRow("example.mode", contains: ["new_choice", "Choices: new_choice, idle"])
        reveal("example.signed")
        assertRow("example.signed", contains: ["2.5", "Fresh"])
        capture("remap-after")
    }

    func testUnavailableScenariosShowNoDiscoveredValues() {
        for scenario in ["discoveredUnsupported", "discoveredUnusable", "discoveredCatalogFailure"] {
            open(scenario)
            assertState("Telemetry unavailable")
            XCTAssertFalse(row("example.enabled").exists)
            capture(scenario + "-unavailable")
            closeSheet()
            XCTAssertTrue(app.buttons["Drive"].exists)
            app.terminate()
        }
    }

    func testLargeTextScrollAndAccessibilityLabels() {
        open("discoveredSignals", largeText: true)
        assertRow("example.enabled", contains: ["example.enabled, Boolean, True, Fresh", "Unit: none", "Catalog evidence: reference"])
        capture("large-text-first-row")
        reveal("example.mode")
        assertRow("example.mode", contains: ["example.mode, Enum, new_choice, Unverified", "Choices: idle, new_choice"])
        reveal("example.signed")
        assertRow("example.signed", contains: ["example.signed, Number, -1.25, Fresh", "Unit: m/s^2"])
        capture("large-text-scrolled-number")
        XCTAssertTrue(app.buttons["signals.close"].isHittable)
        closeSheet()
    }

    private func open(_ scenario: String, largeText: Bool = false) {
        app.launchArguments = ["-FakeController", "YES", "-DemoScenario", scenario]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        openSheet()
    }

    private func openSheet() {
        let button = app.buttons["signals.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 35))
        for _ in 0..<8 {
            if button.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable, "Discovered signals must be reachable on the dashboard")
        button.tap()
        XCTAssertTrue(app.buttons["signals.close"].waitForExistence(timeout: 5))
    }

    private func row(_ key: String) -> XCUIElement {
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        return app.descendants(matching: .any)["signals.row." + hex].firstMatch
    }

    private func assertRow(_ key: String, contains texts: [String], timeout: TimeInterval = 20,
                           file: StaticString = #filePath, line: UInt = #line) {
        let element = row(key)
        let predicate = NSPredicate { _, _ in
            element.exists && texts.allSatisfy { element.label.contains($0) }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout),
                       .completed, "\(key) did not show \(texts): \(element.exists ? element.label : "missing")", file: file, line: line)
    }

    private func assertState(_ text: String, timeout: TimeInterval = 20) {
        let state = app.descendants(matching: .any)["signals.state"].firstMatch
        let predicate = NSPredicate { _, _ in state.exists && state.label.contains(text) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout), .completed)
    }

    private func reveal(_ key: String) {
        let scroll = app.scrollViews["signals.list"]
        for _ in 0..<8 {
            if row(key).exists && row(key).isHittable { return }
            scroll.swipeUp()
        }
        XCTAssertTrue(row(key).isHittable, "row not reachable by scrolling: \(key)")
    }

    private func closeSheet() {
        app.buttons["signals.close"].tap()
        XCTAssertTrue(app.buttons["signals.open"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
