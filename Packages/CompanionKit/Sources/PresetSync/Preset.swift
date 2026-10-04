import Foundation
import CompanionProtocol

/// A bundled, complete schema version 1 config the user can push to the
/// controller. Every preset starts from the factory profile.
public struct Preset: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// One sentence on how the preset differs from the factory profile.
    public var summary: String
    public var config: ControllerConfig

    public init(id: String, name: String, summary: String, config: ControllerConfig) {
        self.id = id
        self.name = name
        self.summary = summary
        self.config = config
    }

    /// What each action does, in plain language.
    public var actionDescriptions: [ActionDescription] {
        ConfigDescriber.describe(config)
    }
}

/// The presets that ship with the app, from `Presets/` in this module.
///
/// Each preset is a canonical config document (`<id>.json`) listed in
/// `index.json`. `factory.json` is a verbatim copy of the firmware's factory
/// profile, `docs/specs/configuration/examples/controller-config-v1.json`.
public enum PresetCatalog {
    public enum LoadError: Error, Equatable {
        case missingResource(String)
    }

    private struct Entry: Decodable {
        var id: String
        var name: String
        var summary: String
        var file: String
    }

    /// The bundled presets, in display order.
    public static func bundled() throws -> [Preset] {
        let entries = try JSONDecoder().decode([Entry].self, from: resource("index.json"))
        return try entries.map { entry in
            Preset(
                id: entry.id,
                name: entry.name,
                summary: entry.summary,
                config: try ControllerConfig(canonicalJSON: resource(entry.file))
            )
        }
    }

    /// The firmware's embedded factory profile, which Revert to factory restores.
    public static func factory() throws -> ControllerConfig {
        try ControllerConfig(canonicalJSON: resource("factory.json"))
    }

    /// The raw bytes of a bundled file.
    public static func resource(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Presets") else {
            throw LoadError.missingResource(name)
        }
        return try Data(contentsOf: url)
    }
}
