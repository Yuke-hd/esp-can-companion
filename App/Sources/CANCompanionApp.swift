import SwiftUI
import Observation
import CoreBluetooth
import DesignSystem
import BLETransport
import CompanionLink
import PresetSync

@MainActor
final class CANCompanionAppDelegate: NSObject, UIApplicationDelegate {
    private(set) var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        orientationMask
    }

    func setOrientation(_ orientation: DriveOrientation) {
        orientationMask = orientation == .landscape ? .landscape : .portrait
        requestGeometryUpdate()
    }

    func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private func requestGeometryUpdate() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: orientationMask)
        ) { _ in }
    }
}

@main
struct CANCompanionApp: App {
    @State private var model = AppModel.launch()
    @UIApplicationDelegateAdaptor(CANCompanionAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(model: model, appDelegate: appDelegate)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
                // Text stops growing at the default size, whatever the
                // system text size; layouts are not designed beyond it.
                .dynamicTypeSize(...DynamicTypeSize.large)
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
    /// The app's own display settings; never follows the controller's config.
    var appConfig: AppConfig {
        didSet { appConfigStore.appConfig = appConfig }
    }
    @ObservationIgnored private let makeSession: @MainActor () -> ControllerSession
    @ObservationIgnored private let appConfigStore: AppConfigStore

    init(session: ControllerSession, appConfigStore: AppConfigStore? = nil) {
        self.session = session
        presetSync = Self.makePresetSync(session)
        makeSession = { session }
        // The in-memory default is for previews and tests; `launch()` passes the persistent store.
        let appConfigStore = appConfigStore ?? InMemoryAppConfigStore()
        self.appConfigStore = appConfigStore
        appConfig = appConfigStore.appConfig.validated
    }

    /// Defers the session, and with it the system Bluetooth prompt, until
    /// `allowBluetooth()`.
    init(
        deferring makeSession: @escaping @MainActor () -> ControllerSession,
        appConfigStore: AppConfigStore? = nil
    ) {
        self.makeSession = makeSession
        let appConfigStore = appConfigStore ?? InMemoryAppConfigStore()
        self.appConfigStore = appConfigStore
        appConfig = appConfigStore.appConfig.validated
    }

    var needsBluetoothPermission: Bool { session == nil }

    /// Applies and saves `band` only when it is valid. Otherwise returns the
    /// rule it breaks and leaves the live and saved band as they were.
    @discardableResult
    func setRPMBand(_ band: RPMBand) -> RPMBandIssue? {
        if let issue = band.issue { return issue }
        appConfig.rpmBand = band
        return nil
    }

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
    /// `-ResetAppConfig YES` forgets saved app settings before loading them.
    static func launch() -> AppModel {
        let defaults = UserDefaults.standard
        let configStore = UserDefaultsAppConfigStore(defaults: defaults)
        if defaults.bool(forKey: "ResetAppConfig") {
            configStore.reset()
        }
        if let name = defaults.string(forKey: "DemoScenario"), let scenario = DemoScenario(rawValue: name) {
            return AppModel(session: scenario.makeSession(), appConfigStore: configStore)
        }
        #if targetEnvironment(simulator)
        return AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: configStore)
        #else
        if defaults.bool(forKey: "FakeController") {
            return AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: configStore)
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
            return AppModel(deferring: make, appConfigStore: configStore)
        }
        return AppModel(session: make(), appConfigStore: configStore)
        #endif
    }
}
