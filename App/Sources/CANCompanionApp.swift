import SwiftUI
import DesignSystem
import BLETransport

@main
struct CANCompanionApp: App {
    @State private var connection = CANCompanionApp.makeConnectionManager()

    var body: some Scene {
        WindowGroup {
            HomeView(connection: connection)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
        }
    }

    /// The Simulator has no Bluetooth radio, so it uses the in-memory fake
    /// controller. Pass `-FakeController YES` as a launch argument to use the
    /// fake on a device too.
    @MainActor
    private static func makeConnectionManager() -> ConnectionManager {
        #if targetEnvironment(simulator)
        let useFake = true
        #else
        let useFake = UserDefaults.standard.bool(forKey: "FakeController")
        #endif
        if useFake {
            return .demo(autoConnect: false)
        }
        let manager = ConnectionManager(
            radio: CoreBluetoothRadio(),
            store: UserDefaultsDeviceStore(),
            scheduler: MainActorScheduler()
        )
        manager.start()
        return manager
    }
}
