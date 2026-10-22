import EngineSound
import EngineSimCore
import XCTest
@testable import CANCompanion

final class EngineSimSourceTests: XCTestCase {
    func testLSV8ContainsExpectedFiringOrderWithoutChangingItsVoice() throws {
        for rpm in [1500.0, 3000, 5000] {
            let source: any EngineSoundSource = try EngineSimSource(profile: .lsV8)
            source.setTargetRPM(rpm)
            source.setThrottle(0.5)
            source.setIgnition(true)
            _ = render(source, seconds: 2)
            let samples = render(source, seconds: 0.5)
            let expected = rpm / 15
            // Isolate the fourth crank order from adjacent half-orders. The
            // original cross-plane exhaust can have a stronger lower order;
            // this checks firing-order presence, not the loudest engine note.
            let halfOrderMidpoint = rpm / 240
            let frequency = dominantFrequency(samples, band:
                Int((expected - halfOrderMidpoint).rounded(.up))...Int((expected + halfOrderMidpoint).rounded(.down)))
            print("LS V8 \(rpm) RPM: firing-order peak \(frequency) Hz, expected \(rpm / 15)")
            XCTAssertEqual(frequency, rpm / 15, accuracy: rpm / 15 * 0.03)
        }
    }

    func testTargetChangeIsAudibleWithinThreeHundredMilliseconds() throws {
        let source = try EngineSimSource(profile: .lsV8)
        source.setTargetRPM(1500)
        source.setThrottle(0.5)
        source.setIgnition(true)
        _ = render(source, seconds: 0.7)
        source.setTargetRPM(3000)
        let transition = render(source, seconds: 0.3)
        XCTAssertEqual(dominantFrequency(Array(transition.suffix(4410))), 200, accuracy: 6)
    }

    func testIgnitionOffProducesSilenceAfterBufferedAudio() throws {
        let source = try EngineSimSource(profile: .lsV8)
        source.setTargetRPM(3000)
        source.setThrottle(0.5)
        source.setIgnition(true)
        _ = render(source, seconds: 0.5)
        source.setIgnition(false)
        XCTAssertTrue(render(source, seconds: 0.3).allSatisfy { $0 == 0 })
    }

    func testRepeatedCreationAndDestruction() throws {
        for _ in 0..<20 {
            let source = try EngineSimSource(profile: .lsV8)
            XCTAssertEqual(source.sampleRate, 44100)
            XCTAssertEqual(render(source, seconds: 0.02).count, 882)
        }
    }

    func testBridgeRejectsInvalidArgumentsAndIgnoresNonfiniteControls() throws {
        engine_sim_destroy(nil)
        engine_sim_set_target_rpm(nil, 3000)
        engine_sim_set_throttle(nil, 0.5)
        engine_sim_set_ignition(nil, 1)
        XCTAssertNil(engine_sim_create(EngineSimProfile(rawValue: 99), 0))
        XCTAssertEqual(engine_sim_render(nil, nil, 1), 0)
        let bridge = try XCTUnwrap(engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0))
        defer { engine_sim_destroy(bridge) }
        XCTAssertEqual(engine_sim_render(bridge, nil, 1), 0)
        var frame: Int16 = 123
        XCTAssertEqual(engine_sim_render(bridge, &frame, -1), 0)
        XCTAssertEqual(frame, 123)
        engine_sim_set_target_rpm(bridge, .nan)
        engine_sim_set_target_rpm(bridge, .infinity)
        engine_sim_set_throttle(bridge, .nan)
        engine_sim_set_throttle(bridge, -.infinity)
        var samples = [Int16](repeating: 123, count: 882)
        XCTAssertEqual(engine_sim_render(bridge, &samples, 882), 882)
        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }

    func testEmptyRenderAndControlsPreserveDefaultSilence() throws {
        let source = try EngineSimSource(profile: .lsV8)
        var empty: [Int16] = []
        XCTAssertEqual(empty.withUnsafeMutableBufferPointer { source.render(into: $0) }, 0)
        source.setTargetRPM(3000)
        source.setThrottle(1)
        XCTAssertTrue(render(source, seconds: 0.1).allSatisfy { $0 == 0 })
    }

    func testNativeCrankSpeedMatchesAllRequestedSpeeds() throws {
        for rpm in [1500.0, 3000, 5000] {
            let core = try XCTUnwrap(engine_sim_create_ls_v8(0))
            defer { engine_sim_destroy(core) }
            engine_sim_set_target_rpm(core, rpm)
            engine_sim_set_throttle(core, 0.5)
            engine_sim_set_ignition(core, 1)
            var samples = [Int16](repeating: 0, count: 30870)
            XCTAssertEqual(engine_sim_render(core, &samples, Int32(samples.count)), Int32(samples.count))
            XCTAssertEqual(engine_sim_rpm(core), rpm, accuracy: rpm * 0.02)
        }
    }

    private func render(_ source: any EngineSoundSource, seconds: Double) -> [Int16] {
        var samples = [Int16](repeating: 0, count: Int(seconds * source.sampleRate))
        let count = samples.withUnsafeMutableBufferPointer { source.render(into: $0) }
        XCTAssertEqual(count, samples.count)
        return samples
    }

    // Hann-windowed spectral peak over the specified physical engine-order band.
    private func dominantFrequency(_ samples: [Int16], band: ClosedRange<Int> = 60...400) -> Double {
        let values = samples.enumerated().map { index, sample in
            Double(sample) * (0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(samples.count - 1)))
        }
        var best = (frequency: 0.0, power: 0.0)
        var edgePower = 0.0
        for frequency in band {
            // Goertzel evaluates the full-sample DFT without downsampling or
            // aliasing, with one recurrence per sample and frequency bin.
            let coefficient = 2 * cos(2 * .pi * Double(frequency) / 44100)
            var previous = 0.0, beforePrevious = 0.0
            for sample in values {
                let current = sample + coefficient * previous - beforePrevious
                beforePrevious = previous
                previous = current
            }
            let power = previous * previous + beforePrevious * beforePrevious
                - coefficient * previous * beforePrevious
            if frequency == band.lowerBound || frequency == band.upperBound { edgePower += power }
            if power > best.power { best = (Double(frequency), power) }
        }
        if band.count < 100 {
            XCTAssertGreaterThan(best.power, edgePower * 2,
                "firing-order peak must exceed the mean band-edge power by 4x")
        }
        return best.frequency
    }
}
