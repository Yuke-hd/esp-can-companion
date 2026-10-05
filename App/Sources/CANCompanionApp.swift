import SwiftUI
import Observation
import CoreBluetooth
import DesignSystem
import BLETransport
import CompanionLink
import PresetSync

@main
struct CANCompanionApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
        }
    }
}

/// App-wide state. Holds the controller session, or, before the user has
/// been asked for Bluetooth access, what creates it.
@MainActor
@Observable
final class AppModel {
    /// Nil until the user allows Bluetooth on first launch.
    private(set) var session: ControllerSession? = nil
    private(set) var presetSync: PresetSyncModel?
    @ObservationIgnored private let makeSession: @MainActor () -> ControllerSession

    init(session: ControllerSession) {
        self.session = session
        presetSync = Self.makePresetSync(session)
        makeSession = { session }
    }

    /// Defers the session, and with it the system Bluetooth prompt, until
    /// `allowBluetooth()`.
    init(deferring makeSession: @escaping @MainActor () -> ControllerSession) {
        self.makeSession = makeSession
    }

    var needsBluetoothPermission: Bool { session == nil }

    /// Cached preset identity is confirmed only by the current session's read.
    var hasCurrentPresetRead: Bool {
        guard session?.phase == .ready,
              let status = session?.configStatus, let active = presetSync?.active else { return false }
        return status.activeSource == active.source && status.activeCRC32 == active.crc32
    }

    /// Creates the session. On a device this shows the system Bluetooth prompt.
    func allowBluetooth() {
        guard session == nil else { return }
        session = makeSession()
        if let session { presetSync = Self.makePresetSync(session) }
    }

    private static func makePresetSync(_ session: ControllerSession) -> PresetSyncModel {
        PresetSyncModel(presets: (try? PresetCatalog.bundled()) ?? [], link: session)
    }

    /// The Simulator has no Bluetooth radio, so it uses the in-memory fake
    /// controller. Pass `-FakeController YES` to use the fake on a device too,
    /// and `-DemoScenario <name>` (see `DemoScenario`) to start in another state.
    static func launch() -> AppModel {
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "DemoScenario"), let scenario = DemoScenario(rawValue: name) {
            return AppModel(session: scenario.makeSession())
        }
        #if targetEnvironment(simulator)
        let useFake = true
        #else
        let useFake = defaults.bool(forKey: "FakeController")
        #endif
        if useFake {
            return AppModel(session: DemoScenario.notPaired.makeSession())
        }

        let make: @MainActor () -> ControllerSession = {
            let manager = ConnectionManager(
                radio: CoreBluetoothRadio(),
                store: UserDefaultsDeviceStore(),
                scheduler: MainActorScheduler()
            )
            manager.start()
            return ControllerSession(connection: manager)
        }
        // Creating the radio is what triggers the system prompt, so explain
        // first. Once decided (or on a background relaunch for state
        // restoration), create it right away.
        if CBManager.authorization == .notDetermined {
            return AppModel(deferring: make)
        }
        return AppModel(session: make())
    }
}
