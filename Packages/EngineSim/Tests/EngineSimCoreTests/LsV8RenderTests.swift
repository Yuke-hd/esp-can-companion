import EngineSimCore
import XCTest

final class LsV8RenderTests: XCTestCase {
    private let sampleRate = Int(ENGINE_SIM_SAMPLE_RATE)

    func testHoldsThreeThousandRpmAndRendersUnclippedAudio() throws {
        let core = try XCTUnwrap(engine_sim_create_ls_v8(0))
        defer { engine_sim_destroy(core) }

        engine_sim_hold_rpm(core, 3000)

        let half = sampleRate / 2
        var warmup = [Int16](repeating: 0, count: half)
        XCTAssertEqual(engine_sim_render(core, &warmup, Int32(half)), Int32(half))

        let rpmAfterHalfSecond = engine_sim_rpm(core)
        XCTAssertEqual(rpmAfterHalfSecond, 3000, accuracy: 3000 * 0.02)

        let remaining = 2 * sampleRate - half
        var tail = [Int16](repeating: 0, count: remaining)
        XCTAssertEqual(engine_sim_render(core, &tail, Int32(remaining)), Int32(remaining))
        XCTAssertEqual(engine_sim_rpm(core), 3000, accuracy: 3000 * 0.02)

        let samples = warmup + tail
        let peak = samples.map { abs(Int32($0)) }.max() ?? 0
        let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()

        XCTAssertGreaterThan(rms, 100, "output is silent")
        XCTAssertLessThan(peak, Int32(Int16.max), "output is clipped")
    }

    /// Reports the real-time factor (rendered audio seconds per wall-clock second)
    /// at the default and a reduced simulation frequency, with physics and audio
    /// overlapped (`engine_sim_render`) and serialized (`engine_sim_render_synchronous`).
    /// A factor above 1 keeps up with playback.
    func testReportsRealTimeFactor() throws {
        let renderers: [(String, (OpaquePointer, UnsafeMutablePointer<Int16>, Int32) -> Int32)] = [
            ("overlapped", engine_sim_render),
            ("synchronous", engine_sim_render_synchronous),
        ]
        for (label, render) in renderers {
            for frequency in [Int(ENGINE_SIM_DEFAULT_FREQUENCY), 5000] {
                let core = try XCTUnwrap(engine_sim_create_ls_v8(Int32(frequency)))
                defer { engine_sim_destroy(core) }
                engine_sim_hold_rpm(core, 3000)

                let seconds = 10
                var samples = [Int16](repeating: 0, count: seconds * sampleRate)
                let start = DispatchTime.now().uptimeNanoseconds
                let written = render(core, &samples, Int32(samples.count))
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9

                XCTAssertEqual(Int(written), samples.count)
                XCTAssertEqual(Int(engine_sim_simulation_frequency(core)), frequency)
                print("BENCHMARK LS V8 \(frequency) Hz \(label): \(String(format: "%.2f", Double(seconds) / elapsed))x real time")
            }
        }
    }
}
