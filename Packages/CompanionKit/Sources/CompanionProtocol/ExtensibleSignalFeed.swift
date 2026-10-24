import Foundation

public struct ExtensibleSignalSnapshot: Equatable, Sendable {
    public let catalog: SignalCatalog?
    public let sequence: UInt16?
    public let isTelemetryStarted: Bool
    public let isStalled: Bool
    public let signals: [ExtensibleSignalState]
    public var needsCatalog: Bool { catalog == nil }

    /// Wire strings use exact UTF-8 identity, including canonically equivalent keys.
    public func reading(for key: String) -> SignalReading<ExtensibleSignalValue>? {
        signals.first { $0.descriptor.key.utf8.elementsEqual(key.utf8) }?.reading
    }
}

public struct ExtensibleSignalState: Equatable, Sendable {
    public let descriptor: SignalDescriptor
    public let reading: SignalReading<ExtensibleSignalValue>
    /// Monotonic receipt time of this typed value, retained across unrelated
    /// packets. Nil when the value is missing, invalid, expired, or stalled.
    public let receivedAt: ContinuousClock.Instant?

    public init(
        descriptor: SignalDescriptor,
        reading: SignalReading<ExtensibleSignalValue>,
        receivedAt: ContinuousClock.Instant? = nil
    ) {
        self.descriptor = descriptor
        self.reading = reading
        self.receivedAt = receivedAt
    }
}

/// Latest state only, at most 64 entries. The caller supplies its monotonic
/// clock and resets this feed on reconnect, security loss or CCCD disable.
public struct ExtensibleSignalFeed: Sendable {
    public static let stallTimeout: Duration = .seconds(2)
    public static let signalTimeout: Duration = .seconds(3)
    public private(set) var catalog: SignalCatalog?
    private var readings: [UInt16: SignalReading<ExtensibleSignalValue>] = [:]
    private var recordTimes: [UInt16: ContinuousClock.Instant] = [:]
    private var packetTime: ContinuousClock.Instant?
    private var sequence: UInt16?
    private var telemetryStarted = false

    public init() {}

    /// Only a complete, validated catalog may resume decoding. Installing even
    /// the same token discards readings and clocks from the previous connection.
    public mutating func install(catalog: SignalCatalog) {
        reset()
        self.catalog = catalog
    }

    public mutating func reset() {
        catalog = nil
        readings.removeAll(keepingCapacity: true)
        recordTimes.removeAll(keepingCapacity: true)
        packetTime = nil
        sequence = nil
        telemetryStarted = false
    }

    public var stallDeadline: ContinuousClock.Instant? { packetTime.map { $0 + Self.stallTimeout } }
    public func livenessDeadline(for handle: UInt16) -> ContinuousClock.Instant? {
        recordTimes[handle].map { $0 + Self.signalTimeout }
    }

    @discardableResult
    public mutating func receive(_ data: Data, at now: ContinuousClock.Instant) -> ExtensibleLiveSignalPacket? {
        guard let catalog else { return nil }
        // Format and framing must be valid before any record or clock is applied.
        // A recognizable header with a different token invalidates even if its
        // records are malformed; the old mapping is no longer trustworthy.
        if data.count >= 8, data.first == 1 {
            var header = ByteReader(Data(data.prefix(8)))
            _ = try? header.bytes(4, "header")
            if let token = try? header.u32("catalog_token"), token != catalog.token {
                reset()
                return nil
            }
        }
        guard let packet = try? ExtensibleLiveSignalPacket(decoding: data), packet.token == catalog.token else { return nil }
        if packetTime.map({ now - $0 >= Self.stallTimeout }) == true {
            readings.removeAll(keepingCapacity: true)
        }
        for record in packet.records {
            guard let descriptor = catalog.descriptor(for: record.handle) else { continue }
            readings[record.handle] = record.reading(for: descriptor)
            if record.type == descriptor.type.rawValue { recordTimes[record.handle] = now }
        }
        packetTime = now
        sequence = packet.sequence
        telemetryStarted = packet.isTelemetryStarted
        return packet
    }

    public func snapshot(at now: ContinuousClock.Instant) -> ExtensibleSignalSnapshot {
        let stalled = packetTime.map { now - $0 >= Self.stallTimeout } ?? true
        let states: [ExtensibleSignalState] = catalog?.descriptors.map { descriptor in
            let expired = recordTimes[descriptor.handle].map { now - $0 >= Self.signalTimeout } ?? true
            let reading: SignalReading<ExtensibleSignalValue> = stalled || expired
                ? .unknown : readings[descriptor.handle] ?? .unknown
            return ExtensibleSignalState(descriptor: descriptor, reading: reading,
                receivedAt: reading.value == nil ? nil : recordTimes[descriptor.handle])
        } ?? []
        return ExtensibleSignalSnapshot(catalog: catalog, sequence: sequence,
            isTelemetryStarted: !stalled && telemetryStarted, isStalled: stalled, signals: states)
    }
}
