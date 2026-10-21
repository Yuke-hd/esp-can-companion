import XCTest
import PresetSync
import CompanionProtocol
import SwiftUI
@testable import CANCompanion

@MainActor
final class SetupSelectionTests: XCTestCase {
    func testInvalidRPMRelationshipsDisableSendAndCorrectionOrResetRestoresIt() throws {
        let selection = SetupSelection()
        selection.select(try XCTUnwrap(PresetCatalog.bundled().first))
        selection.setRPMInputRange(.init(lower: 6000, upper: 6000))
        XCTAssertTrue(selection.hasInputErrors)
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
        selection.setRPMInputRange(.init(lower: 1001, upper: 6000))
        XCTAssertTrue(selection.canSend(isConnected: true, phase: .idle))
        selection.setRedZoneThresholds(.init(triggerAbove: 6000, releaseBelow: 5800))
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
        selection.setRedZoneThresholds(.init(triggerAbove: 5999, releaseBelow: 5999))
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
        selection.resetTweaks()
        XCTAssertFalse(selection.hasInputErrors)
        XCTAssertTrue(selection.canSend(isConnected: true, phase: .idle))
    }

    func testFullRuleEditsCannotBypassRPMValidation() throws {
        let selection = SetupSelection()
        selection.select(try XCTUnwrap(PresetCatalog.bundled().first))
        var config = try XCTUnwrap(selection.editableConfig)
        config.rules.append(.range(.init(action: "rpm_fill", signalKey: "vehicle.engine_rpm",
                                         input: .init(from: -1, to: 6000), output: .init(from: 0, to: 1))))
        selection.updateConfig(config)
        XCTAssertTrue(selection.hasInputErrors)
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
    }

    func testSliderRoundsFloatingPointNoiseToHundredRPMWithoutRoundingTextEntry() {
        var rpm = 6001.0
        let textValue = Binding(get: { rpm }, set: { rpm = $0 })
        let slider = rpmSliderBinding(textValue)
        XCTAssertEqual(slider.wrappedValue, 6001)

        for noisyValue in [6399.999999999999, 6400.000000000001] {
            slider.wrappedValue = noisyValue
            XCTAssertEqual(rpm, 6400)
            XCTAssertEqual(SetupNumericEntry.formatted(rpm), "6400")
        }
        slider.wrappedValue = 6351
        XCTAssertEqual(rpm, 6400)
        textValue.wrappedValue = 6499
        XCTAssertEqual(slider.wrappedValue, 6499)
        XCTAssertEqual(rpm, 6499)
    }

    func testRPMTextEntryAllowsOneRPMPrecisionWithoutAcceptingFractions() {
        let fine: Double? = SetupNumericEntry.parse("3001", integerOnly: true)
        let fraction: Double? = SetupNumericEntry.parse("3001.5", integerOnly: true)
        let general: Double? = SetupNumericEntry.parse("0.25", integerOnly: false)
        XCTAssertEqual(fine, 3001)
        XCTAssertNil(fraction)
        XCTAssertEqual(general, 0.25)
        XCTAssertEqual(SetupNumericEntry.formatted(3001.0), "3001")
    }

    func testFineRPMEditsAreNotRoundedToSliderSteps() throws {
        let selection = SetupSelection()
        selection.select(try XCTUnwrap(PresetCatalog.bundled().first))
        selection.setRPMInputRange(.init(lower: 1001, upper: 6499))
        selection.setRedZoneThresholds(.init(triggerAbove: 6001, releaseBelow: 5799))
        XCTAssertEqual(selection.tweaks?.rpmInputRange, .init(lower: 1001, upper: 6499))
        XCTAssertEqual(selection.tweaks?.redZoneThresholds, .init(triggerAbove: 6001, releaseBelow: 5799))
    }

    func testSelectingPresetDoesNotClaimItIsOnCarUntilControllerMatches() throws {
        let preset = try XCTUnwrap(PresetCatalog.bundled().first)
        let selection = SetupSelection()
        selection.select(preset)

        XCTAssertEqual(selection.preset, preset)
        XCTAssertEqual(selection.status(activePresetID: nil), .pending)
        XCTAssertEqual(selection.status(activePresetID: preset.id), .onCar)
    }

    func testDisconnectedOrBusyControllerCannotSendSelectedPreset() throws {
        let preset = try XCTUnwrap(PresetCatalog.bundled().first)
        let selection = SetupSelection()
        selection.select(preset)

        XCTAssertFalse(selection.canSend(isConnected: false, phase: .idle))
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .uploading(preset, fraction: 0.5)))
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .confirming(.preset(preset))))
        XCTAssertTrue(selection.canSend(isConnected: true, phase: .idle))
    }

    func testNoSelectionCannotSendAndControllerFactoryIsNotPresetMatch() throws {
        let selection = SetupSelection()
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
        XCTAssertEqual(selection.status(activePresetID: nil), .none)
        selection.select(try XCTUnwrap(PresetCatalog.bundled().first))
        XCTAssertEqual(selection.status(activePresetID: nil), .pending)
    }

    func testDraftFollowsTheControllersConfigUntilTheUserChoosesOrEdits() throws {
        let presets = try PresetCatalog.bundled()
        let factory = try PresetCatalog.factory()
        let selection = SetupSelection()
        selection.selectFallback(presets[0])
        XCTAssertEqual(selection.basePreset, presets[0])

        let onFactory = PresetSyncModel.ActiveConfig(source: .known(.factory), crc32: 0,
                                                     config: factory)
        selection.followController(onFactory, presets: presets)
        XCTAssertTrue(selection.isControllerBase)
        XCTAssertEqual(selection.preset?.config, factory)
        XCTAssertEqual(selection.status(active: onFactory), .onCar)

        let onTrack = PresetSyncModel.ActiveConfig(source: .known(.persistedOverride), crc32: 0, presetID: presets[1].id,
                                                   config: presets[1].config)
        selection.followController(onTrack, presets: presets)
        XCTAssertEqual(selection.preset, presets[1])
        XCTAssertEqual(selection.status(active: onTrack), .onCar)

        selection.setRPMInputRange(.init(lower: 1_200, upper: 6_400))
        selection.followController(onFactory, presets: presets)
        XCTAssertEqual(selection.basePreset, presets[1])

        selection.resetTweaks()
        selection.select(presets[2])
        selection.followController(onFactory, presets: presets)
        XCTAssertEqual(selection.preset, presets[2])
        XCTAssertEqual(selection.status(active: onFactory), .pending)
    }

    func testTweakingPresetCreatesDistinctUploadIdentityAndResetRestoresBase() throws {
        let base = try XCTUnwrap(PresetCatalog.bundled().first)
        let selection = SetupSelection()
        selection.select(base)
        selection.setRPMInputRange(.init(lower: 1_200, upper: 6_400))

        XCTAssertEqual(selection.basePreset, base)
        XCTAssertNotEqual(selection.preset?.id, base.id)
        XCTAssertTrue(selection.isModified)
        XCTAssertEqual(selection.changeCount, 1)
        XCTAssertEqual(selection.status(activePresetID: base.id), .pending)
        selection.resetTweaks()
        XCTAssertEqual(selection.preset, base)
        XCTAssertFalse(selection.isModified)
        XCTAssertEqual(selection.changeCount, 0)
    }

    func testGenericRuleEditCountsAndRestoringItsValueClearsModifications() throws {
        let base = try XCTUnwrap(PresetCatalog.bundled().first)
        let selection = SetupSelection()
        selection.select(base)
        var config = base.config
        config.rules.append(.state(.init(action: "left_turn", signalKey: "custom.signal", comparison: .equal, operand: .boolean(true))))
        selection.updateConfig(config)
        XCTAssertEqual(selection.editableConfig, config)
        XCTAssertEqual(selection.changeCount, 1)
        selection.updateConfig(base.config)
        XCTAssertFalse(selection.isModified)
        XCTAssertEqual(selection.preset, base)
    }

    func testCatalogOutputAndSinkEditsPreserveUnlistedBindings() throws {
        let selection = SetupSelection()
        var base = try XCTUnwrap(PresetCatalog.bundled().first)
        base.config.outputs.append(.unknown(.object(["type": .string("future_output"), "action": .string("future")])))
        let fillIndex = try XCTUnwrap(base.config.outputs.firstIndex(where: { $0.action == "rpm_fill" }))
        selection.select(base)
        selection.setCatalogField("zone", value: .object(["start": .number(4), "length": .number(20),
                                                           "direction": .string("start_to_end")]),
                                  outputType: "led_fill", outputIndex: fillIndex)
        selection.setCatalogField("effect", value: .string("brake"), outputType: "led_effect", outputIndex: 3)
        selection.setCatalogSinkSetting("pixel_count", value: .number(175), sink: "local_argb")
        let edited = try XCTUnwrap(selection.editableConfig)
        XCTAssertEqual(edited.sinks["local_argb"]?.object?["pixel_count"], .number(175))
        XCTAssertEqual(edited.outputs.last, base.config.outputs.last)
        XCTAssertEqual(edited.outputs.first(where: { $0.action == "rpm_fill" })?.action, "rpm_fill")
        guard case .ledFill = try XCTUnwrap(edited.outputs.first(where: { $0.action == "rpm_fill" })) else {
            return XCTFail("Known catalog output types remain represented as known bindings")
        }
        guard case .ledEffect(let firstHazard) = edited.outputs[2],
              case .ledEffect(let secondHazard) = edited.outputs[3] else {
            return XCTFail("Duplicate actions remain represented as their distinct output bindings")
        }
        XCTAssertEqual(firstHazard.effect, .leftTurn)
        XCTAssertEqual(secondHazard.effect, .brake)
        XCTAssertTrue(selection.isModified)
    }

    func testReselectingBaseKeepsTweaksAndSelectingAnotherBaseResetsThem() throws {
        let presets = try PresetCatalog.bundled()
        let selection = SetupSelection()
        selection.select(presets[0])
        selection.setRPMInputRange(.init(lower: 1_200, upper: 6_400))
        let edited = selection.preset
        selection.select(presets[0])
        XCTAssertEqual(selection.preset, edited)
        selection.select(presets[1])
        XCTAssertEqual(selection.preset, presets[1])
        XCTAssertFalse(selection.isModified)
    }

    func testEditedPresetOnlyReportsOnCarForMatchingPersistedConfigCRC() throws {
        let base = try XCTUnwrap(PresetCatalog.bundled().first)
        let selection = SetupSelection()
        selection.select(base)
        selection.setRPMInputRange(.init(lower: 1_200, upper: 6_400))
        let edited = try XCTUnwrap(selection.preset)
        let editedCRC = CRC32.checksum(try edited.config.encodedJSON())
        let baseCRC = CRC32.checksum(try base.config.encodedJSON())
        XCTAssertEqual(selection.status(activeSource: .known(.persistedOverride), activeCRC32: baseCRC), .pending)
        XCTAssertEqual(selection.status(activeSource: .known(.factory), activeCRC32: editedCRC), .pending)
        XCTAssertEqual(selection.status(activeSource: .known(.persistedOverride), activeCRC32: editedCRC), .onCar)
        XCTAssertEqual(selection.status(active: nil), .pending)
    }

    func testInvalidNumericFieldsDisableSendingUntilEveryEntryIsCorrected() throws {
        let selection = SetupSelection()
        selection.select(try XCTUnwrap(PresetCatalog.bundled().first))
        selection.setFieldValidity("zone.length", isValid: false)
        selection.setFieldValidity("rpm.from", isValid: false)
        XCTAssertTrue(selection.hasInputErrors)
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
        selection.setFieldValidity("zone.length", isValid: true)
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
        selection.setFieldValidity("rpm.from", isValid: true)
        XCTAssertFalse(selection.hasInputErrors)
        XCTAssertTrue(selection.canSend(isConnected: true, phase: .idle))
    }

    func testReturningToSetupRestoresSendGuardForRetainedInvalidEntry() throws {
        let selection = SetupSelection()
        selection.select(try XCTUnwrap(PresetCatalog.bundled().first))
        let fieldID = "setup.rpm.from"
        let retainedText = "-"
        let parsedValue: Int? = SetupNumericEntry.parse(retainedText, integerOnly: true)

        selection.setFieldValidity(fieldID, isValid: parsedValue != nil)
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))

        // SetupNumberField clears its registration when its tab disappears.
        selection.setFieldValidity(fieldID, isValid: true)
        XCTAssertTrue(selection.canSend(isConnected: true, phase: .idle))

        // On reappearance, it registers the validity of its retained text again.
        selection.setFieldValidity(fieldID, isValid: parsedValue != nil)
        XCTAssertTrue(selection.hasInputErrors)
        XCTAssertFalse(selection.canSend(isConnected: true, phase: .idle))
    }

    func testDiscardingDraftClearsItsInvalidFieldState() throws {
        let presets = try PresetCatalog.bundled()
        let selection = SetupSelection()
        selection.select(presets[0])
        selection.setFieldValidity("zone.length", isValid: false)
        selection.resetTweaks()
        XCTAssertFalse(selection.hasInputErrors)
        selection.setFieldValidity("zone.length", isValid: false)
        selection.select(presets[1])
        XCTAssertFalse(selection.hasInputErrors)
    }

}
