import SwiftUI
import CompanionProtocol
import CompanionLink

/// The Drive route owns one live subscription while its landscape screen is
/// present. The root removes this route when another tab is selected.
struct DriveTab: View {
    let model: AppModel
    let onExit: () -> Void
    @State private var telemetry: LiveTelemetry?
    @AppStorage(DriveStyle.storageKey) private var style: DriveStyle = .motorsport

    init(model: AppModel, onExit: @escaping () -> Void) {
        self.model = model
        self.onExit = onExit
        _telemetry = State(initialValue: model.session.map(LiveTelemetry.init))
    }

    var body: some View {
        let session = model.session
        let summary = session?.activeConfig?.configSummary
        let frame = telemetry?.frame ?? .unknown
        let appConfig = model.appConfig
        let readout = DriveReadout(
            frame: frame,
            activeConfig: summary,
            rpmBand: appConfig.rpmBand,
            snapshot: telemetry?.snapshot,
            brakePressureBarScale: appConfig.brakePressureBarScale,
            linkState: session?.connection.state ?? .unknown,
            framesPerSecond: telemetry?.framesPerSecond ?? 0
        )

        let signals = MotorsportSignals(frame: frame, readout: readout)

        Group {
            switch style {
            case .motorsport:
                MotorsportDriveView(
                    readout: readout,
                    signals: signals,
                    telemetryFailure: telemetry?.failure,
                    onExit: onExit,
                    onSwitchStyle: switchStyle
                )
            case .cluster:
                ClusterDriveView(
                    readout: readout,
                    signals: signals,
                    rpmBand: appConfig.rpmBand,
                    onExit: onExit,
                    onSwitchStyle: switchStyle
                )
            }
        }
            .task(id: session?.phase) {
                guard let session, session.phase == .ready else { return }
                let liveTelemetry: LiveTelemetry
                if let telemetry {
                    liveTelemetry = telemetry
                } else {
                    let created = LiveTelemetry(session: session)
                    telemetry = created
                    liveTelemetry = created
                }
                await liveTelemetry.run()
            }
    }

    private func switchStyle() {
        style = style.next
    }
}

/// The Drive presentations the driver can switch between; the choice is kept
/// across launches.
enum DriveStyle: String, CaseIterable {
    case motorsport
    case cluster

    /// Shared by the Drive cycle button and the App settings picker.
    static let storageKey = "drive.style"

    var title: String {
        switch self {
        case .motorsport: "Motorsport"
        case .cluster: "Cluster"
        }
    }

    var next: DriveStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
