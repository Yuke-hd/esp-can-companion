import Foundation

/// The Device info characteristic: versions and limits, readable before pairing.
public struct DeviceInfo: Equatable, Sendable {
    public var protocolMajor: UInt8
    public var protocolMinor: UInt8
    /// The persisted config schema version the firmware accepts.
    public var configSchemaVersion: UInt16
    public var liveSignalLayoutVersion: UInt8
    /// Raw flag bits. Unknown bits are kept but ignored.
    public var flags: UInt8
    /// Largest config document the controller accepts over BLE.
    public var maxConfigBytes: UInt16
    /// Informational; never parsed for compatibility.
    public var firmwareVersion: String
    /// Informational board record identifier.
    public var hardwareID: String

    public init(
        protocolMajor: UInt8,
        protocolMinor: UInt8,
        configSchemaVersion: UInt16,
        liveSignalLayoutVersion: UInt8,
        flags: UInt8,
        maxConfigBytes: UInt16,
        firmwareVersion: String,
        hardwareID: String
    ) {
        self.protocolMajor = protocolMajor
        self.protocolMinor = protocolMinor
        self.configSchemaVersion = configSchemaVersion
        self.liveSignalLayoutVersion = liveSignalLayoutVersion
        self.flags = flags
        self.maxConfigBytes = maxConfigBytes
        self.firmwareVersion = firmwareVersion
        self.hardwareID = hardwareID
    }

    /// Flags bit 0: the controller accepts a new pairing right now.
    public var isPairingWindowOpen: Bool { flags & 0x01 != 0 }

    /// Decodes a device info value. Bytes after the known fields are ignored,
    /// as a later protocol minor version may append fields.
    public init(decoding data: Data) throws {
        var reader = ByteReader(data)
        protocolMajor = try reader.u8("protocol_major")
        protocolMinor = try reader.u8("protocol_minor")
        configSchemaVersion = try reader.u16("config_schema_version")
        liveSignalLayoutVersion = try reader.u8("live_signal_layout_version")
        flags = try reader.u8("flags")
        maxConfigBytes = try reader.u16("max_config_bytes")
        firmwareVersion = try reader.lengthPrefixedString("firmware_version")
        hardwareID = try reader.lengthPrefixedString("hardware_id")
    }

    /// Checks this controller against what the client supports, following the
    /// compatibility rule in the core profile.
    public func compatibility(
        supportedProtocolMajors: Set<UInt8> = CompanionProtocol.supportedProtocolMajors,
        knownProtocolMinor: UInt8 = CompanionProtocol.knownProtocolMinor,
        supportedConfigSchemaVersions: Set<UInt16> = CompanionProtocol.supportedConfigSchemaVersions,
        supportedLiveSignalLayouts: Set<UInt8> = CompanionProtocol.supportedLiveSignalLayouts
    ) -> Compatibility {
        guard supportedProtocolMajors.contains(protocolMajor) else {
            return Compatibility(
                isProtocolSupported: false,
                hasNewerMinor: false,
                canEditConfig: false,
                canDecodeLiveSignals: false
            )
        }
        return Compatibility(
            isProtocolSupported: true,
            hasNewerMinor: protocolMinor > knownProtocolMinor,
            canEditConfig: supportedConfigSchemaVersions.contains(configSchemaVersion),
            canDecodeLiveSignals: supportedLiveSignalLayouts.contains(liveSignalLayoutVersion)
        )
    }
}

/// What the client may do with a controller, given its device info.
public struct Compatibility: Equatable, Sendable {
    /// False when the protocol major is not supported. The client must then
    /// not pair, write a config, send a command or decode live signals; the
    /// app or the firmware needs an update.
    public var isProtocolSupported: Bool
    /// The controller speaks a newer minor version. It is still compatible;
    /// unknown fields, flag bits and codes are ignored.
    public var hasNewerMinor: Bool
    /// The controller's config schema is one `ControllerConfig` models. When
    /// false, a read-back can only be shown as opaque JSON.
    public var canEditConfig: Bool
    /// The live signals layout is one this client decodes. When false, the
    /// client does not subscribe.
    public var canDecodeLiveSignals: Bool
}
