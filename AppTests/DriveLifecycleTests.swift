import XCTest
@testable import CANCompanion

@MainActor
final class DriveLifecycleTests: XCTestCase {
    func testAppDelegatePublishesCurrentOrientationMask() {
        let appDelegate = CANCompanionAppDelegate()

        XCTAssertEqual(appDelegate.orientationMask, .portrait)
        appDelegate.setOrientation(.landscape)
        XCTAssertEqual(appDelegate.orientationMask, .landscape)
        appDelegate.setOrientation(.portrait)
        XCTAssertEqual(appDelegate.orientationMask, .portrait)
    }

    func testDriveAppearingWhileAppIsActiveDisablesIdleTimerAndUsesLandscape() {
        var orientations: [DriveOrientation] = []
        var idleTimerValues: [Bool] = []
        let lifecycle = DriveLifecycleCoordinator(
            setOrientation: { orientations.append($0) },
            setIdleTimerDisabled: { idleTimerValues.append($0) }
        )

        lifecycle.setAppActive(true)
        lifecycle.setDriveVisible(true)

        XCTAssertEqual(orientations, [.portrait, .landscape])
        XCTAssertEqual(idleTimerValues, [true])
    }

    func testLeavingDriveRestoresPortraitAndReenablesIdleTimer() {
        var orientations: [DriveOrientation] = []
        var idleTimerValues: [Bool] = []
        let lifecycle = DriveLifecycleCoordinator(
            setOrientation: { orientations.append($0) },
            setIdleTimerDisabled: { idleTimerValues.append($0) }
        )

        lifecycle.setAppActive(true)
        lifecycle.setDriveVisible(true)
        lifecycle.setDriveVisible(false)

        XCTAssertEqual(orientations, [.portrait, .landscape, .portrait])
        XCTAssertEqual(idleTimerValues, [true, false])
    }

    func testBackgroundReenablesIdleTimerUntilDriveBecomesActiveAgain() {
        var idleTimerValues: [Bool] = []
        let lifecycle = DriveLifecycleCoordinator(
            setOrientation: { _ in },
            setIdleTimerDisabled: { idleTimerValues.append($0) }
        )

        lifecycle.setAppActive(true)
        lifecycle.setDriveVisible(true)
        lifecycle.setAppActive(false)
        lifecycle.setAppActive(true)

        XCTAssertEqual(idleTimerValues, [true, false, true])
    }
}
