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
        XCTAssertEqual(GMeterModel.Configuration.standard.expandedRange, 1.0)

        var model = GMeterModel()
        model.update(GForce(longitudinal: -1.2, lateral: 1.6), at: at(0))
        XCTAssertEqual(model.ringRange, 1.0, "beyond the compact ring the range expands")

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
            compactRange: 0.5,
            expandedRange: 1.0,
            shrinkThreshold: 0.45,
            rangeSettle: .seconds(3),
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

    // MARK: Auto-range

    /// The standard configuration without peak hold, so the range follows the
    /// smoothed magnitude alone, and with near-instant smoothing so each
    /// sample is effectively the smoothed value.
    private var magnitudeOnly: GMeterModel.Configuration {
        var configuration = GMeterModel.Configuration.standard
        configuration.peakHold = .zero
        configuration.peakDecay = .zero
        configuration.smoothingTimeConstant = .milliseconds(1)
        return configuration
    }

    private func lateral(_ g: Double) -> GForce {
        GForce(longitudinal: 0, lateral: g)
    }

    func testStandardAutoRangeConfiguration() {
        let configuration = GMeterModel.Configuration.standard
        XCTAssertEqual(configuration.compactRange, 0.5)
        XCTAssertEqual(configuration.expandedRange, 1.0)
        XCTAssertEqual(configuration.shrinkThreshold, 0.45)
        XCTAssertEqual(configuration.rangeSettle, .seconds(3))
    }

    func testRangeIsCompactAtStartAndWithNoData() {
        var model = GMeterModel()
        XCTAssertEqual(model.ringRange, 0.5, "at start")

        model.update(lateral(0.8), at: at(0))
        XCTAssertEqual(model.ringRange, 1.0)

        model.update(nil, at: at(100))
        XCTAssertEqual(model.ringRange, 0.5, "no data resets to the compact range")
    }

    func testRangeExpandsWhenTheTotalMagnitudeExceedsTheCompactRing() {
        var atRing = GMeterModel()
        atRing.update(lateral(0.5), at: at(0))
        XCTAssertEqual(atRing.ringRange, 0.5, "exactly on the ring does not expand")

        // Neither axis alone exceeds 0.5 g, but the total does.
        var combined = GMeterModel()
        combined.update(GForce(longitudinal: -0.4, lateral: 0.35), at: at(0))
        XCTAssertEqual(combined.ringRange, 1.0)
    }

    func testValuesInsideTheCompactRangeAreNotClampedOrRescaled() throws {
        var model = GMeterModel()
        model.update(GForce(longitudinal: -0.3, lateral: 0.2), at: at(0))

        let dot = try XCTUnwrap(model.dot)
        XCTAssertEqual(dot.y, 0.3, accuracy: accuracy)
        XCTAssertEqual(dot.x, -0.2, accuracy: accuracy)
    }

    func testRangeShrinksOnlyAfterTheMagnitudeSettlesBelowTheThreshold() {
        var model = GMeterModel(configuration: magnitudeOnly)
        model.update(lateral(0.6), at: at(0))
        XCTAssertEqual(model.ringRange, 1.0)

        model.update(lateral(0.1), at: at(1000))
        model.update(lateral(0.1), at: at(3999))
        XCTAssertEqual(model.ringRange, 1.0, "still inside the settle period")

        model.update(lateral(0.1), at: at(4000))
        XCTAssertEqual(model.ringRange, 0.5, "three seconds below the threshold")
    }

    func testRangeDoesNotFlickerAroundTheThreshold() {
        var model = GMeterModel(configuration: magnitudeOnly)
        model.update(lateral(0.6), at: at(0))

        // Between the shrink threshold and the ring: no shrink, however long.
        for second in 1...6 {
            model.update(lateral(0.48), at: at(second * 1000))
        }
        XCTAssertEqual(model.ringRange, 1.0, "hysteresis band holds the expanded range")

        // A dip below the threshold starts the settle period; rising back
        // above it restarts the period.
        model.update(lateral(0.3), at: at(7000))
        model.update(lateral(0.48), at: at(8000))
        model.update(lateral(0.3), at: at(9000))
        model.update(lateral(0.3), at: at(11999))
        XCTAssertEqual(model.ringRange, 1.0, "the settle period restarted at 9 s")
        model.update(lateral(0.3), at: at(12000))
        XCTAssertEqual(model.ringRange, 0.5)

        // Once compact, values up to the ring do not expand it again.
        model.update(lateral(0.48), at: at(13000))
        model.update(lateral(0.49), at: at(14000))
        XCTAssertEqual(model.ringRange, 0.5)

        // Expanding again during a settle period discards it: the next dip
        // starts a fresh period.
        model = GMeterModel(configuration: magnitudeOnly)
        model.update(lateral(0.6), at: at(20000))
        model.update(lateral(0.3), at: at(21000))
        model.update(lateral(0.6), at: at(22000))
        model.update(lateral(0.3), at: at(24100))
        XCTAssertEqual(model.ringRange, 1.0, "the settle period restarted at 24.1 s")
        model.update(lateral(0.3), at: at(27099))
        XCTAssertEqual(model.ringRange, 1.0)
        model.update(lateral(0.3), at: at(27100))
        XCTAssertEqual(model.ringRange, 0.5)
    }

    func testAHeldPeakAboveTheThresholdKeepsTheRangeExpanded() {
        var model = GMeterModel()
        model.update(lateral(0.6), at: at(0))
        model.update(lateral(0), at: at(1000))
        XCTAssertEqual(model.ringRange, 1.0, "the dot is near the centre but the 0.6 g peak is held")

        // At 3 s the peak has decayed to 0.3 g, below the threshold, so the
        // settle period starts there rather than when the dot returned.
        model.update(lateral(0), at: at(3000))
        model.update(lateral(0), at: at(5999))
        XCTAssertEqual(model.ringRange, 1.0)
        model.update(lateral(0), at: at(6000))
        XCTAssertEqual(model.ringRange, 0.5)
    }

    func testPeaksAndTrailKeepTheirValuesInGAcrossARangeChange() throws {
        var model = GMeterModel()
        model.update(lateral(0.3), at: at(0))
        XCTAssertEqual(model.ringRange, 0.5)
        model.update(lateral(0.9), at: at(200))
        XCTAssertEqual(model.ringRange, 1.0)

        let smoothed = try XCTUnwrap(model.smoothed).lateral
        XCTAssertGreaterThan(smoothed, 0.5)
        XCTAssertEqual(model.peaks.right, smoothed, accuracy: accuracy, "not clamped to the old compact ring")
        XCTAssertEqual(try XCTUnwrap(model.dot).x, -smoothed, accuracy: accuracy)
        let trail = model.trail
        XCTAssertEqual(trail.count, 2)
        XCTAssertEqual(try XCTUnwrap(trail.first).position.x, -0.3, accuracy: accuracy, "the older point stays at 0.3 g")
        XCTAssertEqual(trail.last?.position, model.dot)
    }

    func testTrailIsStoredInGAndClampedOnlyForTheActiveRange() throws {
        var configuration = magnitudeOnly
        configuration.rangeSettle = .zero
        var model = GMeterModel(configuration: configuration)

        model.update(lateral(0.8), at: at(0))
        model.update(lateral(0.1), at: at(100))
        XCTAssertEqual(model.ringRange, 0.5, "a zero settle shrinks at once")
        XCTAssertEqual(try XCTUnwrap(model.trail.first).position.x, -0.5, accuracy: accuracy, "clamped to the compact rim")

        model.update(lateral(0.9), at: at(200))
        XCTAssertEqual(model.ringRange, 1.0)
        XCTAssertEqual(try XCTUnwrap(model.trail.first).position.x, -0.8, accuracy: accuracy, "the stored 0.8 g is back")
    }

    func testPointClampsRadiallyToARadius() {
        let point = GMeterModel.Point(x: 0.6, y: -0.8)
        let clamped = point.clamped(toRadius: 0.5)
        XCTAssertEqual(clamped.x, 0.3, accuracy: accuracy)
        XCTAssertEqual(clamped.y, -0.4, accuracy: accuracy)
        XCTAssertEqual(point.clamped(toRadius: 2), point, "inside the radius is unchanged")
    }

    func testInnerMarksCrossFadeBetweenTheHalfRangeRings() throws {
        let configuration = GMeterModel.Configuration.standard

        func opacities(_ range: Double) -> [Double: Double] {
            Dictionary(uniqueKeysWithValues: configuration.innerMarks(atRange: range).map { ($0.value, $0.opacity) })
        }

        XCTAssertEqual(opacities(0.5), [0.25: 1, 0.5: 0], "±0.5 g shows the 0.25 g ring inside the 0.5 g rim")
        XCTAssertEqual(opacities(1.0), [0.25: 0, 0.5: 1], "±1 g shows the 0.5 g ring inside the 1 g rim")
        let halfway = opacities(0.75)
        XCTAssertEqual(try XCTUnwrap(halfway[0.25]), 0.5, accuracy: accuracy)
        XCTAssertEqual(try XCTUnwrap(halfway[0.5]), 0.5, accuracy: accuracy)
        XCTAssertEqual(opacities(2.0), [0.25: 0, 0.5: 1], "outside the ranges the nearest end applies")
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
