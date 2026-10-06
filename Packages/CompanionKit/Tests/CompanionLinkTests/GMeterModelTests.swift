import XCTest
@testable import CompanionLink

final class GMeterModelTests: XCTestCase {
    private let start = ContinuousClock().now
    private let accuracy = 0.0001

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start + .milliseconds(milliseconds)
    }

    // MARK: Smoothing

    func testFirstSampleIsShownWithoutRampingFromZero() throws {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -0.4, lateral: 0.2), at: at(0))

        let smoothed = try XCTUnwrap(model.smoothed)
        XCTAssertEqual(smoothed.longitudinal, -0.4, accuracy: accuracy)
        XCTAssertEqual(smoothed.lateral, 0.2, accuracy: accuracy)
    }

    func testSmoothingStepResponseReaches63PercentAfterOneTimeConstant() throws {
        var model = GMeterModel()
        model.update(GForce(longitudinal: 0, lateral: 0), at: at(0))
        // Ten 15 ms frames make one 150 ms time constant, independent of frame rate.
        for step in 1...10 {
            model.update(GForce(longitudinal: 1, lateral: -1), at: at(step * 15))
        }

        let expected = 1 - exp(-1.0)
        let smoothed = try XCTUnwrap(model.smoothed)
        XCTAssertEqual(smoothed.longitudinal, expected, accuracy: accuracy)
        XCTAssertEqual(smoothed.lateral, -expected, accuracy: accuracy)
        XCTAssertEqual(GMeterModel.Configuration.standard.smoothingTimeConstant, .milliseconds(150))
    }

    func testOneLargeStepMatchesManySmallSteps() throws {
        var model = GMeterModel()
        model.update(GForce(longitudinal: 0, lateral: 0), at: at(0))
        model.update(GForce(longitudinal: 1, lateral: 0), at: at(150))

        XCTAssertEqual(try XCTUnwrap(model.smoothed).longitudinal, 1 - exp(-1.0), accuracy: accuracy)
    }

    // MARK: Dot direction and ring clamp

    func testDotMovesTowardTheForceFeltByOccupantsByDefault() throws {
        XCTAssertEqual(GMeterModel.Configuration.standard.dotDirection, .feltForce)

        var braking = GMeterModel()
        braking.update(GForce(longitudinal: -0.5, lateral: 0), at: at(0))
        XCTAssertEqual(try XCTUnwrap(braking.dot).y, 0.5, accuracy: accuracy, "braking moves the dot up")

        var accelerating = GMeterModel()
        accelerating.update(GForce(longitudinal: 0.5, lateral: 0), at: at(0))
        XCTAssertEqual(try XCTUnwrap(accelerating.dot).y, -0.5, accuracy: accuracy, "accelerating moves it down")

        var rightTurn = GMeterModel()
        rightTurn.update(GForce(longitudinal: 0, lateral: 0.5), at: at(0))
        XCTAssertEqual(try XCTUnwrap(rightTurn.dot).x, -0.5, accuracy: accuracy, "a right turn moves it left")
    }

    func testFlippingTheDotDirectionMirrorsBothAxes() throws {
        var configuration = GMeterModel.Configuration.standard
        configuration.dotDirection = .acceleration
        var model = GMeterModel(configuration: configuration)
        model.update(GForce(longitudinal: -0.5, lateral: 0.25), at: at(0))

        let dot = try XCTUnwrap(model.dot)
        XCTAssertEqual(dot.y, -0.5, accuracy: accuracy)
        XCTAssertEqual(dot.x, 0.25, accuracy: accuracy)
    }

    func testDotBeyondTheRingClampsToTheRimWithoutRescaling() throws {
        XCTAssertEqual(GMeterModel.Configuration.standard.ringRange, 1.0)

        var model = GMeterModel()
        model.update(GForce(longitudinal: -1.2, lateral: 1.6), at: at(0))

        let dot = try XCTUnwrap(model.dot)
        XCTAssertEqual(hypot(dot.x, dot.y), 1.0, accuracy: accuracy)
        XCTAssertEqual(dot.y, 0.6, accuracy: accuracy)
        XCTAssertEqual(dot.x, -0.8, accuracy: accuracy)
        // The underlying value is kept, so numeric text still reports 2 g.
        XCTAssertEqual(try XCTUnwrap(model.smoothed).magnitude, 2.0, accuracy: accuracy)

        var inside = GMeterModel()
        inside.update(GForce(longitudinal: 0.3, lateral: 0), at: at(0))
        XCTAssertEqual(try XCTUnwrap(inside.dot).y, -0.3, accuracy: accuracy, "values inside the ring are not rescaled")
    }

    // MARK: Peak hold and decay

    func testPeaksTrackEachDirectionSeparately() {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -0.6, lateral: 0.3), at: at(0))
        model.update(GForce(longitudinal: 0.4, lateral: -0.2), at: at(1000))

        // A long gap makes the smoothed value settle on each input; the brake
        // and right peaks are still inside their hold time.
        XCTAssertEqual(model.peaks.brake, 0.6, accuracy: 0.01)
        XCTAssertEqual(model.peaks.right, 0.3, accuracy: 0.01)
        XCTAssertEqual(model.peaks.accel, 0.4, accuracy: 0.01)
        XCTAssertEqual(model.peaks.left, 0.2, accuracy: 0.01)
    }

    func testPeakHoldsForTwoSecondsThenDecaysToZeroOverTwoMore() {
        let configuration = GMeterModel.Configuration.standard
        XCTAssertEqual(configuration.peakHold, .seconds(2))
        XCTAssertEqual(configuration.peakDecay, .seconds(2))

        var model = GMeterModel()
        let calm = GForce(longitudinal: 0, lateral: 0)
        model.update(GForce(longitudinal: -0.8, lateral: 0), at: at(0))
        model.update(calm, at: at(2000))
        XCTAssertEqual(model.peaks.brake, 0.8, accuracy: accuracy, "held for the full hold time")

        model.update(calm, at: at(3000))
        XCTAssertEqual(model.peaks.brake, 0.4, accuracy: accuracy, "halfway through the decay")

        model.update(calm, at: at(4000))
        XCTAssertEqual(model.peaks.brake, 0, accuracy: accuracy, "fully decayed")

        model.update(calm, at: at(6000))
        XCTAssertEqual(model.peaks.brake, 0, accuracy: accuracy)
    }

    func testANewHigherPeakRestartsTheHold() {
        var model = GMeterModel()
        model.update(GForce(longitudinal: 0, lateral: 0.5), at: at(0))
        model.update(GForce(longitudinal: 0, lateral: 0.9), at: at(3000))
        model.update(GForce(longitudinal: 0, lateral: 0), at: at(5000))

        XCTAssertEqual(model.peaks.right, 0.9, accuracy: 0.01)
    }

    func testALowerSampleDuringTheHoldDoesNotRestartIt() {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -0.8, lateral: 0), at: at(0))
        model.update(GForce(longitudinal: -0.5, lateral: 0), at: at(1000))
        model.update(GForce(longitudinal: 0, lateral: 0), at: at(3000))

        // The hold started at 0 ms, so 3 s in the 0.8 g peak is halfway through
        // its decay; a restarted hold would still read 0.8 or 0.5.
        XCTAssertEqual(model.peaks.brake, 0.4, accuracy: 0.01)
    }

    func testAPeakAboveTheRingDecaysFromItsRealValue() {
        var model = GMeterModel()
        let calm = GForce(longitudinal: 0, lateral: 0)
        model.update(GForce(longitudinal: -1.6, lateral: 0), at: at(0))
        XCTAssertEqual(model.peaks.brake, 1.0, accuracy: accuracy, "presented at the rim")

        // The stored peak is 1.6 g, so the marker dwells on the rim until the
        // decay brings it below the ring: 1.6 × (1 − 0.25) = 1.2 is still clamped.
        model.update(calm, at: at(2500))
        XCTAssertEqual(model.peaks.brake, 1.0, accuracy: accuracy, "still on the rim")

        model.update(calm, at: at(3000))
        XCTAssertEqual(model.peaks.brake, 0.8, accuracy: accuracy, "1.6 g halfway through the decay")
    }

    func testPeakPositionsFollowTheDotDirectionAndClampToTheRing() throws {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -1.5, lateral: 0.5), at: at(0))

        XCTAssertEqual(model.peaks.brake, 1.0, accuracy: accuracy, "presentation peaks clamp to the ring")
        let brake = model.peakPosition(.brake)
        XCTAssertEqual(brake.x, 0, accuracy: accuracy)
        XCTAssertEqual(brake.y, 1.0, accuracy: accuracy)
        let right = model.peakPosition(.right)
        XCTAssertEqual(right.x, -0.5, accuracy: accuracy)
        XCTAssertEqual(right.y, 0, accuracy: accuracy)
    }

    // MARK: Trail

    func testTrailKeepsOnlyTheLastThreeQuartersOfASecond() {
        var model = GMeterModel()
        for step in 0...20 {
            model.update(GForce(longitudinal: 0.1, lateral: 0), at: at(step * 100))
        }

        XCTAssertEqual(GMeterModel.Configuration.standard.trailWindow, .milliseconds(750))
        XCTAssertEqual(model.trail.count, 8, "0, 100 ... 700 ms old")
        XCTAssertEqual(model.trail.first?.age, .milliseconds(700))
        XCTAssertEqual(model.trail.last?.age, .zero)
        XCTAssertEqual(model.trail.last?.position, model.dot)
    }

    func testTrailIsCappedAtTwelvePoints() {
        var model = GMeterModel()
        for step in 0...60 {
            model.update(GForce(longitudinal: 0.1, lateral: 0), at: at(step * 20))
        }

        XCTAssertEqual(GMeterModel.Configuration.standard.trailCapacity, 12)
        XCTAssertEqual(model.trail.count, 12)
        XCTAssertEqual(model.trail.first?.age, .milliseconds(220), "oldest points are dropped first")
    }

    func testNonPositiveTrailCapacityKeepsNoTrailWithoutTrapping() {
        for capacity in [-1, 0] {
            var configuration = GMeterModel.Configuration.standard
            configuration.trailCapacity = capacity
            var model = GMeterModel(configuration: configuration)
            model.update(GForce(longitudinal: 0.1, lateral: 0), at: at(0))
            model.update(GForce(longitudinal: 0.2, lateral: 0), at: at(20))

            XCTAssertTrue(model.trail.isEmpty, "capacity \(capacity)")
            XCTAssertNotNil(model.dot, "capacity \(capacity)")
        }

        let viaInit = GMeterModel.Configuration(
            smoothingTimeConstant: .milliseconds(150),
            peakHold: .seconds(2),
            peakDecay: .seconds(2),
            trailWindow: .milliseconds(750),
            trailCapacity: -1,
            ringRange: 1.0,
            dotDirection: .feltForce
        )
        XCTAssertEqual(viaInit.trailCapacity, 0, "the initialiser clamps a negative capacity")
    }

    func testTrailPointsClampToTheRing() throws {
        var model = GMeterModel()
        model.update(GForce(longitudinal: 3, lateral: 0), at: at(0))

        let point = try XCTUnwrap(model.trail.last)
        XCTAssertEqual(point.position.y, -1.0, accuracy: accuracy)
    }

    // MARK: Stall and no data

    func testNoDataBeforeTheFirstSample() {
        let model = GMeterModel()

        XCTAssertNil(model.smoothed)
        XCTAssertNil(model.dot)
        XCTAssertTrue(model.trail.isEmpty)
        XCTAssertEqual(model.peaks, .zero)
    }

    func testNoDataClearsDotTrailAndPeaksWithoutFabricatingZero() {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -0.7, lateral: 0.3), at: at(0))
        model.update(GForce(longitudinal: -0.7, lateral: 0.3), at: at(100))
        model.update(nil, at: at(200))

        XCTAssertNil(model.smoothed)
        XCTAssertNil(model.dot)
        XCTAssertTrue(model.trail.isEmpty)
        XCTAssertEqual(model.peaks, .zero)
    }

    func testDataAfterAStallStartsFreshInsteadOfInterpolating() throws {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -0.7, lateral: 0), at: at(0))
        model.update(nil, at: at(100))
        model.update(GForce(longitudinal: 0.5, lateral: 0), at: at(200))

        XCTAssertEqual(try XCTUnwrap(model.smoothed).longitudinal, 0.5, accuracy: accuracy)
        XCTAssertEqual(model.trail.count, 1)
        XCTAssertEqual(model.peaks.brake, 0, accuracy: accuracy)
    }

    func testTimeOnlyComesFromTheInjectedInstant() throws {
        // Two models fed identical samples and instants agree exactly, whatever
        // the wall clock does between calls.
        var first = GMeterModel()
        var second = GMeterModel()
        for step in 0...5 {
            let sample = GForce(longitudinal: Double(step) / 10, lateral: 0)
            first.update(sample, at: at(step * 50))
            second.update(sample, at: at(step * 50))
        }
        XCTAssertEqual(first, second)

        // A repeated instant does not advance the filter.
        let before = try XCTUnwrap(first.smoothed)
        first.update(GForce(longitudinal: 1, lateral: 1), at: at(250))
        XCTAssertEqual(first.smoothed, before)
    }

    func testAStrictlyEarlierInstantIsIgnored() {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -0.3, lateral: 0), at: at(100))
        model.update(GForce(longitudinal: -0.3, lateral: 0), at: at(200))
        let before = model

        model.update(GForce(longitudinal: -0.9, lateral: 0.9), at: at(150))

        XCTAssertEqual(model, before)
        XCTAssertEqual(model.trail.last?.age, .zero)
    }
}
