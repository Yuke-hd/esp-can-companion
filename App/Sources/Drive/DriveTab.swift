import SwiftUI
import CompanionLink

/// The Drive route owns one live subscription while its landscape screen is
/// present. The root removes this route when another tab is selected.
struct DriveTab: View {
    let model: AppModel
    let onExit: () -> Void
    @State private var telemetry: LiveTelemetry?

    init(model: AppModel, onExit: @escaping () -> Void) {
        self.model = model
        self.onExit = onExit
        _telemetry = State(initialValue: model.session.map(LiveTelemetry.init))
    }

    var body: some View {
        let session = model.session
        let summary = session?.activeConfig?.configSummary
        let frame = telemetry?.frame ?? .unknown
        let readout = DriveReadout(
            frame: frame,
            activeConfig: summary,
            linkState: session?.connection.state ?? .unknown,
            framesPerSecond: telemetry?.framesPerSecond ?? 0
        )

        MotorsportDriveView(readout: readout, onExit: onExit)
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
}
