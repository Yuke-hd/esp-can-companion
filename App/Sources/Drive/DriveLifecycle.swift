import SwiftUI

/// The orientation that the app requests for the currently visible tab.
enum DriveOrientation: Equatable {
    case portrait
    case landscape
}

/// Coordinates the small amount of app-level state that belongs to Drive.
///
/// Keeping the state transition here makes the screen passive and gives tests
/// a deterministic way to verify that the idle timer never outlives Drive.
@MainActor
final class DriveLifecycleCoordinator {
    private let setOrientation: (DriveOrientation) -> Void
    private let setIdleTimerDisabled: (Bool) -> Void
    private var isDriveVisible = false
    private var isAppActive = false
    private var appliedOrientation: DriveOrientation = .portrait
    private var appliedIdleTimerDisabled = false

    init(
        setOrientation: @escaping (DriveOrientation) -> Void,
        setIdleTimerDisabled: @escaping (Bool) -> Void
    ) {
        self.setOrientation = setOrientation
        self.setIdleTimerDisabled = setIdleTimerDisabled
    }

    func setDriveVisible(_ visible: Bool) {
        guard isDriveVisible != visible else { return }
        isDriveVisible = visible
        synchronize()
    }

    func setAppActive(_ active: Bool) {
        guard isAppActive != active else { return }
        isAppActive = active
        synchronize(appActivityChanged: true)
    }

    private func synchronize(appActivityChanged: Bool = false) {
        let desiredOrientation: DriveOrientation = isDriveVisible ? .landscape : .portrait
        if desiredOrientation != appliedOrientation || appActivityChanged {
            setOrientation(desiredOrientation)
            appliedOrientation = desiredOrientation
        }

        let shouldDisableIdleTimer = isDriveVisible && isAppActive
        guard shouldDisableIdleTimer != appliedIdleTimerDisabled else { return }
        setIdleTimerDisabled(shouldDisableIdleTimer)
        appliedIdleTimerDisabled = shouldDisableIdleTimer
    }
}
