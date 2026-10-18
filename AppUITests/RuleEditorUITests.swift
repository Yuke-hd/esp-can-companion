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

        let editor = app.descendants(matching: .any).matching(identifier: "rules.editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        scrollUntilHittable(editor)
        editor.tap()
        let add = app.buttons["rules.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        scrollUntilHittable(add)
        let action = app.textFields["rule.action"]
        // A tap that lands while the scroll view is still decelerating is dropped.
        for _ in 0..<3 where !action.exists {
            add.tap()
            _ = action.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(action.exists)
        let existing = action.value as? String ?? ""
        action.tap()
        action.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "door_open")
        XCTAssertTrue(app.staticTexts["rule.action.new"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["rule.signal"].exists, "discovered signals are picked, not typed")
        capture("rule-sheet-new-action")

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
        let saved = app.buttons.containing(NSPredicate(format: "label CONTAINS 'door_open'")).firstMatch
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
