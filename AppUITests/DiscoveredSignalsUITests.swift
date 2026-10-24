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
        app.scrollViews["signals.list"].swipeUp()
        capture("discovered-signed-number")
        closeSheet()
        XCTAssertTrue(app.buttons["signals.open"].waitForExistence(timeout: 5))
        openSheet()
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
        assertState("Telemetry stalled", timeout: 60)
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
            !self.row("example.enabled").exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: nil)], timeout: 20), .completed)
        capture("remap-disconnected-cleared")
        openSheet()
        assertRow("example.enabled", contains: ["False", "Fresh"], timeout: 35)
        assertRow("example.mode", contains: ["new_choice", "Choices: new_choice, idle"])
        reveal("example.signed")
        assertRow("example.signed", contains: ["2.5", "Fresh"])
        app.scrollViews["signals.list"].swipeUp()
        capture("remap-after")
    }

    func testUnavailableScenariosShowNoDiscoveredValues() {
        for scenario in ["discoveredUnsupported", "discoveredUnusable", "discoveredCatalogFailure"] {
            let failure = scenario == "discoveredCatalogFailure"
                ? "The controller's signal catalog could not be read."
                : "Live signals are not supported by this controller."
            open(scenario, dashboardFailure: failure)
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
        for page in 1...4 {
            app.scrollViews["signals.list"].swipeUp()
            capture("large-text-number-scroll-\(page)")
        }
        XCTAssertTrue(app.buttons["signals.close"].isHittable)
        closeSheet()
    }

    private func open(_ scenario: String, largeText: Bool = false, dashboardFailure: String? = nil) {
        app.launchArguments = ["-FakeController", "YES", "-DemoScenario", scenario]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        if let dashboardFailure {
            // Failure text changes the telemetry card's height. Wait for that
            // expected terminal state before calculating the sheet-button tap.
            XCTAssertTrue(app.staticTexts[dashboardFailure].waitForExistence(timeout: 35))
        }
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
        // A reachable button may still be moving after dashboard layout or a
        // scroll. Confirm the sheet opened before checking its contents.
        let close = app.buttons["signals.close"]
        button.tap(until: close)
        XCTAssertTrue(close.exists, "Discovered signals sheet did not open")
    }

    private func row(_ key: String, matching predicate: NSPredicate? = nil) -> XCUIElement {
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        let candidates = app.descendants(matching: .any).matching(identifier: "signals.row." + hex)
        return (predicate.map { candidates.matching($0) } ?? candidates).firstMatch
    }

    private func assertRow(_ key: String, contains texts: [String], timeout: TimeInterval = 20,
                           file: StaticString = #filePath, line: UInt = #line) {
        let element = row(key)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: texts.map {
            NSPredicate(format: "label CONTAINS %@", $0)
        })
        let matchingRow = row(key, matching: predicate)
        XCTAssertTrue(matchingRow.waitForExistence(timeout: timeout),
                      "\(key) did not show \(texts): \(element.exists ? element.label : "missing")", file: file, line: line)
    }

    private func assertState(_ text: String, timeout: TimeInterval = 20) {
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "Discovered signals did not show state: \(text)")
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
        let close = app.buttons["signals.close"]
        close.tap(until: close, appearing: false)
        XCTAssertFalse(close.exists, "Discovered signals sheet did not close")
        XCTAssertTrue(app.buttons["signals.open"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
