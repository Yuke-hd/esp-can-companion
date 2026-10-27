import XCTest
@testable import CompanionLink

@MainActor
final class AppConfigStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "AppConfigStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private let custom = AppConfig(
        rpmBand: RPMBand(fill: .init(from: 1000, to: 7200), redline: 6800),
        brakePressureBarScale: 120
    )

    func testEmptyStoreReturnsDefaults() {
        XCTAssertEqual(UserDefaultsAppConfigStore(defaults: defaults).appConfig, .default)
    }

    func testSavedConfigIsRestoredByANewStore() {
        UserDefaultsAppConfigStore(defaults: defaults).appConfig = custom
        XCTAssertEqual(UserDefaultsAppConfigStore(defaults: defaults).appConfig, custom)
    }

    func testRedlineOffRoundTrips() {
        var config = custom
        config.rpmBand.redline = nil
        UserDefaultsAppConfigStore(defaults: defaults).appConfig = config
        XCTAssertNil(UserDefaultsAppConfigStore(defaults: defaults).appConfig.rpmBand.redline)
    }

    func testCorruptDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: UserDefaultsAppConfigStore.defaultKey)
        XCTAssertEqual(UserDefaultsAppConfigStore(defaults: defaults).appConfig, .default)
    }

    func testUnknownVersionFallsBackToDefaults() throws {
        UserDefaultsAppConfigStore(defaults: defaults).appConfig = custom
        let data = try XCTUnwrap(defaults.data(forKey: UserDefaultsAppConfigStore.defaultKey))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = UserDefaultsAppConfigStore.currentVersion + 1
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: UserDefaultsAppConfigStore.defaultKey)
        XCTAssertEqual(UserDefaultsAppConfigStore(defaults: defaults).appConfig, .default)
    }

    func testResetRemovesTheSavedConfig() {
        let store = UserDefaultsAppConfigStore(defaults: defaults)
        store.appConfig = custom
        store.reset()
        XCTAssertNil(defaults.data(forKey: UserDefaultsAppConfigStore.defaultKey))
        XCTAssertEqual(store.appConfig, .default)
    }

    func testInMemoryStoreStartsAtDefaults() {
        let store = InMemoryAppConfigStore()
        XCTAssertEqual(store.appConfig, .default)
        store.appConfig = custom
        XCTAssertEqual(store.appConfig, custom)
    }
}
