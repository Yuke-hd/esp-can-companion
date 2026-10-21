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
        let add = app.buttons["rules.add"]
        app.buttons["Setup"].tap(until: add)
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
        focus(name)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Door open\n")
        XCTAssertTrue(app.staticTexts["Saved as door_open"].waitForExistence(timeout: 5))
        capture("rule-card-named")

        let edits = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rules.edit.'"))
        let edit = edits.element(boundBy: edits.count - 1)
        scrollUntilHittable(edit)
        let action = app.textFields["rule.action"]
        edit.tap(until: action)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.value as? String, "door_open")
        XCTAssertFalse(app.textFields["rule.signal"].exists, "discovered signals are picked, not typed")

        let signal = app.buttons.containing(NSPredicate(format: "label CONTAINS 'example.enabled'")).firstMatch
        app.buttons["rule.signal"].tap(until: signal)
        XCTAssertTrue(signal.waitForExistence(timeout: 5))
        capture("rule-signal-picker")
        signal.tap(until: app.switches["rule.operand.boolean"])
        XCTAssertTrue(app.buttons["rule.signal"].waitForExistence(timeout: 5))
        let picker = app.buttons["rule.signal"]
        XCTAssertTrue("\(picker.label) \(picker.value as? String ?? "")".contains("example.enabled"))
        XCTAssertTrue(app.switches["rule.operand.boolean"].exists, "boolean signal switches the operand to a toggle")
        capture("rule-sheet-signal-chosen")

        app.buttons["rule.save"].tap(until: action, appearing: false)
        let saved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'example.enabled'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        capture("rules-with-door-open")
    }

    func testInspectingUntouchedActionPreservesItsNoncanonicalIdentifier() {
        let index = addRule(named: "door__open")
        let name = app.textFields["rules.name.\(index)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        collapseAndExpandRule(at: index)
        assertStoredAction("door__open", at: index)

        // Focusing and leaving without typing must also preserve the identifier.
        focus(name)
        name.typeText("\n")
        assertStoredAction("door__open", at: index)
        capture("untouched-noncanonical-action")
    }

    func testCollapsingAnEditedActionSavesItsName() {
        let index = addRule(named: "door__open")
        let name = app.textFields["rules.name.\(index)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        focus(name)
        let existing = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Boot open")
        collapseAndExpandRule(at: index)
        assertStoredAction("boot_open", at: index)
        capture("edited-action-saved-on-collapse")
    }

    private func addRule(named action: String) -> Int {
        app.launchArguments = ["-FakeController", "YES", "-DemoScenario", "discoveredSignals"]
        app.launch()
        XCTAssertTrue(app.buttons["Setup"].waitForExistence(timeout: 15))
        let add = app.buttons["rules.add"]
        app.buttons["Setup"].tap(until: add)
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        scrollUntilHittable(add)
        let toggles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rules.toggle.'"))
        let index = toggles.count
        let edit = app.buttons["rules.edit.\(index)"]
        for _ in 0..<3 where !edit.exists {
            add.tap()
            _ = edit.waitForExistence(timeout: 3)
        }
        scrollUntilHittable(edit)
        let field = app.textFields["rule.action"]
        edit.tap(until: field)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let existing = field.value as? String ?? ""
        focus(field)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + action)
        app.buttons["rule.save"].tap(until: field, appearing: false)
        return index
    }

    private func assertStoredAction(_ expected: String, at index: Int) {
        let edit = app.buttons["rules.edit.\(index)"]
        scrollUntilHittable(edit)
        let action = app.textFields["rule.action"]
        edit.tap(until: action)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.value as? String, expected)
        app.buttons["rule.cancel"].tap(until: action, appearing: false)
    }

    private func collapseAndExpandRule(at index: Int) {
        let toggle = app.buttons["rules.toggle.\(index)"]
        let name = app.textFields["rules.name.\(index)"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeDown() }
        XCTAssertTrue(toggle.isHittable)
        toggle.tap(until: name, appearing: false)
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        toggle.tap(until: name)
        XCTAssertTrue(name.waitForExistence(timeout: 5))
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func focus(_ field: XCUIElement) {
        field.tap(until: app.keyboards.firstMatch, timeout: 3)
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
