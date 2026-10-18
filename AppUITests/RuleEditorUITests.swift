import XCTest

final class RuleEditorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    func testAddRuleWithTypedActionAndDiscoveredSignal() {
        app.launchArguments = ["-FakeController", "YES", "-DemoScenario", "discoveredSignals"]
        app.launch()
        XCTAssertTrue(app.buttons["Setup"].waitForExistence(timeout: 15))
        app.buttons["Setup"].tap()

        let add = app.buttons["rules.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        scrollUntilHittable(add)
        let names = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'rules.name.'"))
        let before = names.count
        // A tap that lands while the scroll view is still decelerating is dropped.
        for _ in 0..<3 where names.count == before {
            add.tap()
            _ = names.element(boundBy: before).waitForExistence(timeout: 3)
        }
        let name = names.element(boundBy: before)
        XCTAssertTrue(name.exists)
        scrollUntilHittable(name)
        let existing = name.value as? String ?? ""
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Door open\n")
        XCTAssertTrue(app.staticTexts["Saved as door_open"].waitForExistence(timeout: 5))
        capture("rule-card-named")

        let edits = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rules.edit.'"))
        let edit = edits.element(boundBy: edits.count - 1)
        scrollUntilHittable(edit)
        edit.tap()
        let action = app.textFields["rule.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.value as? String, "door_open")
        XCTAssertFalse(app.textFields["rule.signal"].exists, "discovered signals are picked, not typed")

        app.buttons["rule.signal"].tap()
        let signal = app.buttons.containing(NSPredicate(format: "label CONTAINS 'example.enabled'")).firstMatch
        XCTAssertTrue(signal.waitForExistence(timeout: 5))
        capture("rule-signal-picker")
        signal.tap()
        XCTAssertTrue(app.buttons["rule.signal"].waitForExistence(timeout: 5))
        let picker = app.buttons["rule.signal"]
        XCTAssertTrue("\(picker.label) \(picker.value as? String ?? "")".contains("example.enabled"))
        XCTAssertTrue(app.switches["rule.operand.boolean"].exists, "boolean signal switches the operand to a toggle")
        capture("rule-sheet-signal-chosen")

        app.buttons["rule.save"].tap()
        let saved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'example.enabled'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        capture("rules-with-door-open")
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
