import CompanionLink

import Foundation

/// What the Gauges page's brake pressure scale field holds while being
/// edited. Like `RPMBandDraft`, the edit reaches the live scale only on
/// commit, and only when it is a whole number of bar inside
/// `AppConfig.brakePressureBarScaleRange`.
struct BrakeScaleDraft: Equatable {
    enum Problem: Error, Equatable {
        case notAWholeNumber
        case outOfRange
    }

    var text: String

    init(_ scale: Double) {
        text = SetupNumericEntry.formatted(scale)
    }

    var result: Result<Double, Problem> {
        guard let value = RPMBandDraft.wholeNumber(text) else { return .failure(.notAWholeNumber) }
        guard AppConfig.isValidBrakePressureBarScale(value) else { return .failure(.outOfRange) }
        return .success(value)
    }

    var problem: Problem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    /// A valid draft gives the scale to apply and is shown as a canonical
    /// number; an invalid one is left as typed, so the last committed scale
    /// stays live.
    mutating func commit() -> Result<Double, Problem> {
        let result = result
        if case .success(let scale) = result { text = SetupNumericEntry.formatted(scale) }
        return result
    }
}

extension BrakeScaleDraft.Problem {
    /// The inline message under the brake scale field.
    var message: String {
        let range = AppConfig.brakePressureBarScaleRange
        let bounds = "\(SetupNumericEntry.formatted(range.lowerBound)) to \(SetupNumericEntry.formatted(range.upperBound)) bar"
        return switch self {
        case .notAWholeNumber: "Enter the brake pressure scale as a whole number of bar, \(bounds)."
        case .outOfRange: "Brake pressure scale must be \(bounds)."
        }
    }
}

extension AppModel {
    /// Applies and saves `scale` only when it is in range. Otherwise leaves
    /// the live and saved scale as they were and returns false.
    @discardableResult
    func setBrakePressureBarScale(_ scale: Double) -> Bool {
        guard AppConfig.isValidBrakePressureBarScale(scale) else { return false }
        appConfig.brakePressureBarScale = scale
        return true
    }

    /// Commits the Gauges brake scale draft: applies it when valid, otherwise
    /// keeps the live scale and returns why.
    @discardableResult
    func commitBrakeScale(_ draft: inout BrakeScaleDraft) -> BrakeScaleDraft.Problem? {
        switch draft.commit() {
        case .success(let scale): return setBrakePressureBarScale(scale) ? nil : .outOfRange
        case .failure(let problem): return problem
        }
    }

    /// Restores every app setting: `AppConfig.default` (saved through the
    /// store) and the Motorsport Drive style. The controller is not touched.
    func resetAppSettings(defaults: UserDefaults = .standard) {
        appConfig = .default
        defaults.set(DriveStyle.motorsport.rawValue, forKey: DriveStyle.storageKey)
    }
}
