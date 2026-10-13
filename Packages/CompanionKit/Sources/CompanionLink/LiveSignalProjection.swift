import CompanionProtocol

/// Adapts persistent semantic keys to the curated dashboard model. Runtime
/// handles and unfamiliar keys remain in the original snapshot for consumers.
enum LiveSignalProjection {
    static func frame(from snapshot: ExtensibleSignalSnapshot) -> LiveSignalFrame {
        guard !snapshot.isStalled else { return .unknown }
        var frame = LiveSignalFrame.unknown
        frame.sequence = UInt8(truncatingIfNeeded: snapshot.sequence ?? 0)
        frame.isTelemetryStarted = snapshot.isTelemetryStarted
        frame.engineRPM = number("vehicle.engine_rpm", unit: "rpm", in: snapshot)
        frame.speedKPH = number("vehicle.speed_kph", unit: "km/h", in: snapshot)
        frame.longitudinalAcceleration = number("vehicle.acceleration.longitudinal", unit: "m/s^2", in: snapshot)
        frame.lateralAcceleration = number("vehicle.acceleration.lateral", unit: "m/s^2", in: snapshot)
        frame.turnState = choice("vehicle.turn_state", in: snapshot, values: [
            "unknown": .unknown, "off": .off, "left": .left, "right": .right, "hazard": .hazard])
        frame.selectorPosition = choice("vehicle.selector_position", in: snapshot, values: [
            "unknown": .unknown, "shifting": .shifting, "park": .park, "reverse": .reverse,
            "neutral": .neutral, "drive": .drive])
        frame.actualGear = choice("vehicle.actual_gear", in: snapshot, values: [
            "unknown": .unknown, "park_or_neutral": .parkOrNeutral, "park": .park,
            "neutral": .neutral, "reverse": .reverse, "first": .first, "second": .second,
            "third": .third, "fourth": .fourth, "fifth": .fifth, "sixth": .sixth, "shifting": .shifting])
        frame.frontWiperPosition = choice("vehicle.wiper.front_position", in: snapshot, values: [
            "unknown": .unknown, "off": .off, "on": .on, "high": .high, "intermittent": .intermittent])
        frame.hazardRequest = boolean("vehicle.hazard_request", in: snapshot)
        frame.turnRequestLeft = boolean("vehicle.turn_request.left", in: snapshot)
        frame.turnRequestRight = boolean("vehicle.turn_request.right", in: snapshot)
        frame.indicatorLampLeft = boolean("vehicle.indicator_lamp.left", in: snapshot)
        frame.indicatorLampRight = boolean("vehicle.indicator_lamp.right", in: snapshot)
        frame.liftgateOpen = boolean("vehicle.liftgate_open", in: snapshot)
        frame.doorRearRight = boolean("vehicle.door.rear_right", in: snapshot)
        frame.doorRearLeft = boolean("vehicle.door.rear_left", in: snapshot)
        frame.doorFrontLeftRHD = boolean("vehicle.door.front_left_rhd", in: snapshot)
        frame.doorFrontRightRHD = boolean("vehicle.door.front_right_rhd", in: snapshot)
        frame.doorsUnlocked = boolean("vehicle.doors_unlocked", in: snapshot)
        frame.wiperLow = boolean("vehicle.wiper.low", in: snapshot)
        frame.brakePressed = boolean("vehicle.brake_pressed", in: snapshot)
        // Brake has no verified timeout, including when a provider claims fresh.
        if frame.brakePressed.availability == .fresh {
            frame.brakePressed.availability = .freshnessUnverified
        }
        return frame
    }

    private static func state(_ key: String, type: SignalType, unit: String,
                              in snapshot: ExtensibleSignalSnapshot) -> ExtensibleSignalState? {
        snapshot.signals.first {
            $0.descriptor.key.utf8.elementsEqual(key.utf8) &&
            $0.descriptor.type.known == type && $0.descriptor.unit == unit
        }
    }

    private static func number(_ key: String, unit: String,
                               in snapshot: ExtensibleSignalSnapshot) -> SignalReading<Double> {
        guard let state = state(key, type: .number, unit: unit, in: snapshot) else { return .unknown }
        guard let value = state.reading.value else {
            return SignalReading(availability: state.reading.availability, value: nil)
        }
        guard case .number(let number) = value, number.isFinite else { return .unknown }
        return SignalReading(availability: state.reading.availability, value: Double(number))
    }

    private static func boolean(_ key: String, in snapshot: ExtensibleSignalSnapshot) -> SignalReading<Bool> {
        guard let state = state(key, type: .boolean, unit: "none", in: snapshot) else { return .unknown }
        guard let value = state.reading.value else {
            return SignalReading(availability: state.reading.availability, value: nil)
        }
        guard case .boolean(let boolean) = value else { return .unknown }
        return SignalReading(availability: state.reading.availability, value: boolean)
    }

    private static func choice<E>(_ key: String, in snapshot: ExtensibleSignalSnapshot,
                                   values: [String: E]) -> SignalReading<WireValue<E>>
    where E: RawRepresentable & Equatable & Sendable, E.RawValue == UInt8 {
        guard let state = state(key, type: .enumeration, unit: "none", in: snapshot) else { return .unknown }
        guard let value = state.reading.value else {
            return SignalReading(availability: state.reading.availability, value: nil)
        }
        guard case .enumeration(let choiceKey) = value,
              state.descriptor.choices.contains(where: { $0.key.utf8.elementsEqual(choiceKey.utf8) }),
              let choice = values[choiceKey] else { return .unknown }
        return SignalReading(availability: state.reading.availability, value: .known(choice))
    }
}
