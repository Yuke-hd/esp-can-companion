import Foundation

/// Where the app's own settings are kept between launches.
@MainActor
public protocol AppConfigStore: AnyObject {
    var appConfig: AppConfig { get set }
}

/// Keeps `AppConfig` as versioned JSON in `UserDefaults`. Anything it cannot
/// read, including a newer version, comes back as `AppConfig.default`; an
/// invalid RPM band or brake pressure scale comes back as its default.
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

    /// A value that cannot be encoded (such as NaN) leaves the saved settings as they were.
    public var appConfig: AppConfig {
        get {
            guard let data = defaults.data(forKey: key),
                  let stored = try? JSONDecoder().decode(Stored.self, from: data),
                  stored.version == Self.currentVersion else { return .default }
            return stored.config.validated
        }
        set {
            guard let data = try? JSONEncoder().encode(Stored(version: Self.currentVersion, config: newValue)) else { return }
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
