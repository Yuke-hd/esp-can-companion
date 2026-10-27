import XCTest
import CompanionProtocol
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

    func testStoredInvalidBandLoadsAsTheDefaultBand() {
        var invalid = custom
        invalid.rpmBand = RPMBand(fill: .init(from: 6000, to: 5000), redline: nil)
        let app = AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: InMemoryAppConfigStore(appConfig: invalid))
        XCTAssertEqual(app.appConfig.rpmBand, AppConfig.default.rpmBand)
        XCTAssertEqual(app.appConfig.brakePressureBarScale, 120)
    }

    func testValidRPMBandIsAppliedAndSaved() {
        let store = InMemoryAppConfigStore()
        let app = AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: store)
        let band = RPMBand(fill: .init(from: 1000, to: 5000), redline: 4000)
        XCTAssertNil(app.setRPMBand(band))
        XCTAssertEqual(app.appConfig.rpmBand, band)
        XCTAssertEqual(store.appConfig.rpmBand, band)
    }

    func testInvalidRPMBandIsRejectedAndChangesNothing() {
        let store = InMemoryAppConfigStore(appConfig: custom)
        let app = AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: store)
        let issue = app.setRPMBand(RPMBand(fill: .init(from: 1000, to: 5000), redline: 5500))
        XCTAssertEqual(issue, .redlineAboveFillEnd)
        XCTAssertEqual(app.appConfig, custom)
        XCTAssertEqual(store.appConfig, custom)
    }

    func testAppliedBandReachesDriveAndPitWallReadouts() throws {
        let app = AppModel(session: DemoScenario.notPaired.makeSession())
        var telemetry = DemoTelemetry()
        telemetry.engineRPM = 4200
        let frame = try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion)
        XCTAssertFalse(DriveReadout(frame: frame, rpmBand: app.appConfig.rpmBand).redlineActive)

        XCTAssertNil(app.setRPMBand(RPMBand(fill: .init(from: 0, to: 6500), redline: 4000)))
        let drive = DriveReadout(frame: frame, rpmBand: app.appConfig.rpmBand)
        let pitWall = PitWallReadout(frame: frame, band: app.appConfig.rpmBand)
        XCTAssertTrue(drive.redlineActive)
        // 4000 of 6500 across 15 lights: the tenth light (index 9) is the first red one.
        XCTAssertEqual(drive.firstRedShiftLight, 9)
        XCTAssertEqual(pitWall.firstRedShiftLight, 9)
        XCTAssertEqual(pitWall.redlineFraction, 4000 / 7500)
    }

    func testClusterRPMMarksStopAtTheEditableMaximum() {
        let labels = { (band: RPMBand) in ClusterRPMMarks.marks(for: band).map(\.label) }
        XCTAssertEqual(labels(AppConfig.default.rpmBand), ["0", "1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(labels(RPMBand(fill: .init(from: 0, to: 12_000), redline: nil)).last, "12")
        XCTAssertEqual(labels(RPMBand(fill: .init(from: 0, to: 500), redline: nil)), [])
        // Bands no editor can produce must not trap or hang.
        XCTAssertEqual(labels(RPMBand(fill: .init(from: 0, to: 1e300), redline: nil)), [])
        XCTAssertEqual(labels(RPMBand(fill: .init(from: 0, to: .infinity), redline: .nan)), [])
    }

    func testStoredOutOfRangeBrakeScaleLoadsAsTheDefaultScale() {
        var invalid = custom
        invalid.brakePressureBarScale = 5
        let app = AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: InMemoryAppConfigStore(appConfig: invalid))
        XCTAssertEqual(app.appConfig.brakePressureBarScale, AppConfig.default.brakePressureBarScale)
        XCTAssertEqual(app.appConfig.rpmBand, custom.rpmBand)
    }

    func testResetRestoresAndSavesDefaultsAndTheMotorsportStyle() throws {
        let suite = "AppModelConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(DriveStyle.cluster.rawValue, forKey: DriveStyle.storageKey)
        let store = UserDefaultsAppConfigStore(defaults: defaults)
        store.appConfig = custom
        let app = AppModel(session: DemoScenario.notPaired.makeSession(), appConfigStore: store)
        XCTAssertEqual(app.appConfig, custom)

        app.resetAppSettings(defaults: defaults)

        XCTAssertEqual(app.appConfig, .default)
        XCTAssertEqual(UserDefaultsAppConfigStore(defaults: defaults).appConfig, .default, "the defaults are saved")
        XCTAssertEqual(defaults.string(forKey: DriveStyle.storageKey), DriveStyle.motorsport.rawValue)
    }
}
