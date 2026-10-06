import XCTest
import DesignSystem
import CompanionProtocol
import CompanionLink
@testable import CANCompanion

final class PitWallTextTests: XCTestCase {
    func testProfileTitles() throws {
        XCTAssertEqual(ConfigSummary.Profile.factory.title, "Factory")
        XCTAssertEqual(ConfigSummary.Profile.preset("Track").title, "Track")
        XCTAssertEqual(ConfigSummary.Profile.custom.title, "Custom")

        let summary = ConfigSummary(try ControllerConfig(canonicalJSON: DemoController.factoryDocument), profile: .preset("Calm"))
        XCTAssertEqual(ControllerSession.ActiveConfig.summary(summary).profileTitle, "Calm")
        XCTAssertEqual(ControllerSession.ActiveConfig.none.profileTitle, "None")
        XCTAssertEqual(ControllerSession.ActiveConfig.unreadable("x").profileTitle, "Unknown")
    }

    func testBusAndReadoutText() throws {
        let stalled = PitWallReadout(frame: .unknown)
        XCTAssertEqual(stalled.busTitle, "—")
        XCTAssertEqual(stalled.rpmText, "—")
        XCTAssertEqual(stalled.gearDisplay, "—")
        XCTAssertEqual(stalled.speedText, "—")
        XCTAssertEqual(stalled.rpmAccessibilityText, "Engine RPM, no value, Unknown")

        var telemetry = DemoTelemetry()
        telemetry.engineRPM = 4820
        telemetry.speedKPH = 72
        telemetry.actualGear = .fourth
        let live = PitWallReadout(frame: try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion))
        XCTAssertEqual(live.busTitle, "Listen-only")
        XCTAssertTrue(live.rpmText.hasPrefix("4"))
        XCTAssertTrue(live.rpmText.hasSuffix("820"))
        XCTAssertEqual(live.gearDisplay, "4")
        XCTAssertEqual(live.speedText, "72")
        XCTAssertEqual(live.rpmAccessibilityText, "Engine RPM 4820, Unverified")

        telemetry.isTelemetryStarted = false
        XCTAssertEqual(PitWallReadout(frame: try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion)).busTitle, "Not started")
    }

    func testOutputSwatchIsFullBrightness() {
        let night = ConfigSummary.Output(action: "rpm_fill", title: "Rpm fill", priority: 50, kind: .fill, color: .init(red: 0, green: 16, blue: 32))
        XCTAssertEqual(night.swatch, ColorToken(red: 0, green: 0.5, blue: 1))
        XCTAssertEqual(night.accessibilityText, "Rpm fill, priority 50, Fill")

        let effect = ConfigSummary.Output(action: "left_turn", title: "Left turn", priority: 100, kind: .effect, color: nil)
        XCTAssertEqual(effect.swatch, Theme.Palette.signalYellow)

        let black = ConfigSummary.Output(action: "off", title: "Off", priority: 1, kind: .solid, color: .init(red: 0, green: 0, blue: 0))
        XCTAssertEqual(black.swatch, Theme.Palette.textSecondary)
    }

    func testTabsMatchTheDrafts() {
        XCTAssertEqual(AppTab.allCases.map(\.number), ["01", "02", "03", "04"])
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Pit Wall", "Setup", "Strip", "Drive"])
    }

    func testGearAndSpeedBoxesShowFreshnessOnScreen() throws {
        var telemetry = DemoTelemetry()
        telemetry.speedKPH = 72
        telemetry.actualGear = .fourth
        let cases: [(DemoTelemetry.Status, String, Bool)] = [
            (.fresh, "Fresh", true),
            (.unverified, "Unverified", true),
            (.stale, "Stale", false),
            (.noData, "No data", false),
        ]
        for (status, title, isShown) in cases {
            telemetry.statuses[1] = status
            telemetry.statuses[4] = status
            let readout = PitWallReadout(frame: try LiveSignalFrame(decoding: telemetry.encoded, layoutVersion: telemetry.layoutVersion))
            for box in [readout.gearBox, readout.speedBox] {
                XCTAssertEqual(box.lines.map(\.role), [.label, .value, .freshness])
                XCTAssertEqual(box.lines.last?.text, title, box.label)
                XCTAssertEqual(box.isShown, isShown, box.label)
                XCTAssertTrue(box.accessibilityText.hasSuffix(title), box.label)
            }
            XCTAssertEqual(readout.gearBox.lines[1].text, isShown ? "4" : "—")
            XCTAssertEqual(readout.speedBox.lines[1].text, isShown ? "72" : "—")
        }

        let stalled = PitWallReadout(frame: .unknown)
        XCTAssertEqual(stalled.gearBox.lines.map(\.text), ["Gear", "—", "Unknown"])
        XCTAssertEqual(stalled.speedBox.lines.map(\.text), ["Km/h", "—", "Unknown"])
    }
}
