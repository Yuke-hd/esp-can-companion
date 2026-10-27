import XCTest
import CompanionLink
@testable import CANCompanion

@MainActor
final class AppModelConfigTests: XCTestCase {
    private let custom = AppConfig(
        rpmBand: RPMBand(fill: .init(from: 1000, to: 7200), redline: 6800),
        brakePressureBarScale: 120
    )

    func testAppModelLoadsTheStoredConfig() {
        let store = InMemoryAppConfigStore(appConfig: custom)
        let app = AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: store)
        XCTAssertEqual(app.appConfig, custom)
    }

    func testChangingTheConfigSavesIt() {
        let store = InMemoryAppConfigStore()
        let app = AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: store)
        app.appConfig = custom
        XCTAssertEqual(store.appConfig, custom)
    }

    func testDeferredModelAlsoLoadsTheStoredConfig() {
        let store = InMemoryAppConfigStore(appConfig: custom)
        let app = AppModel(deferring: { DemoScenario.notPaired.makeSession() }, appConfigStore: store)
        XCTAssertEqual(app.appConfig, custom)
    }

    func testModelWithoutAStoreUsesDefaults() {
        XCTAssertEqual(AppModel(session: DemoScenario.notPaired.makeSession()).appConfig, .default)
    }
}
