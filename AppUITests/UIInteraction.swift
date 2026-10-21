import XCTest

extension XCUIElement {
    /// Layout and scroll transitions can consume a tap. Check its outcome
    /// before retrying, so a completed action is never tapped a second time.
    func tap(
        until destination: XCUIElement,
        appearing: Bool = true,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for attempt in 0..<3 {
            if attempt > 0, destination.exists == appearing { return }
            tap()
            let reached = appearing
                ? destination.waitForExistence(timeout: timeout)
                : destination.waitForNonExistence(timeout: timeout)
            if reached { return }
        }
        XCTAssertEqual(destination.exists, appearing,
                       "Tap on \(identifier) did not reach \(destination.identifier)", file: file, line: line)
    }
}
