import Foundation

/// Where the app's own settings are kept between launches.
@MainActor
public protocol AppConfigStore: AnyObject {
    var appConfig: AppConfig { get set }
}

/// Keeps `AppConfig` as versioned JSON in `UserDefaults`. Anything it cannot
/// read, including a newer version, comes back as `AppConfig.default`.
@MainActor
public final class UserDefaultsAppConfigStore: AppConfigStore {
    public static let defaultKey = "CompanionLink.appConfig"
    public static let currentVersion = 1

    private struct Stored: Codable {
        var version: Int
        var config: AppConfig
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsAppConfigStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public var appConfig: AppConfig {
        get {
            guard let data = defaults.data(forKey: key),
                  let stored = try? JSONDecoder().decode(Stored.self, from: data),
                  stored.version == Self.currentVersion else { return .default }
            return stored.config
        }
        set {
            let data = try? JSONEncoder().encode(Stored(version: Self.currentVersion, config: newValue))
            defaults.set(data, forKey: key)
        }
    }

    /// Forgets the saved settings, so the next read returns the defaults.
    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
public final class InMemoryAppConfigStore: AppConfigStore {
    public var appConfig: AppConfig

    public init(appConfig: AppConfig = .default) {
        self.appConfig = appConfig
    }
}
