import SwiftUI
import OSLog
import CompanionProtocol
import CompanionLink

/// The Drive route owns one live subscription while its landscape screen is
/// present. The root removes this route when another tab is selected.
struct DriveTab: View {
    let model: AppModel
    let onExit: () -> Void
    @State private var telemetry: LiveTelemetry?
    @State private var engineSound = DriveEngineSoundController()
    @AppStorage(EngineSoundPreferences.enabledKey) private var soundEnabled = false
    @AppStorage(EngineSoundPreferences.lowersOtherAudioKey) private var lowersOtherAudio = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSoundSettings = false
    @AppStorage("drive.style") private var style: DriveStyle = .motorsport

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
            rpmBand: AppConfig.default.rpmBand,
            snapshot: telemetry?.snapshot,
            brakePressureBarScale: AppConfig.default.brakePressureBarScale,
            linkState: session?.connection.state ?? .unknown,
            framesPerSecond: telemetry?.framesPerSecond ?? 0
        )

        let signals = MotorsportSignals(frame: frame, readout: readout)
        let rpmReceivedAt = DriveEngineSoundController.rpmReceiptTime(in: telemetry?.snapshot)

        Group {
            switch style {
            case .motorsport:
                MotorsportDriveView(
                    readout: readout,
                    signals: signals,
                    telemetryFailure: telemetry?.failure,
                    onExit: onExit,
                    onSwitchStyle: switchStyle,
                    isSoundEnabled: soundEnabled,
                    onSoundSettings: { showingSoundSettings = true }
                )
            case .cluster:
                ClusterDriveView(
                    readout: readout,
                    signals: signals,
                    rpmBand: AppConfig.default.rpmBand,
                    onExit: onExit,
                    onSwitchStyle: switchStyle,
                    isSoundEnabled: soundEnabled,
                    onSoundSettings: { showingSoundSettings = true }
                )
            }
        }
            .sheet(isPresented: $showingSoundSettings) {
                EngineSoundSettings(isEnabled: $soundEnabled, lowersOtherAudio: $lowersOtherAudio)
            }
            .onAppear { configureSound(readout: readout, receivedAt: rpmReceivedAt) }
            .onChange(of: scenePhase) { configureSound(readout: readout, receivedAt: rpmReceivedAt) }
            .onChange(of: soundEnabled) { configureSound(readout: readout, receivedAt: rpmReceivedAt) }
            .onChange(of: lowersOtherAudio) { configureSound(readout: readout, receivedAt: rpmReceivedAt) }
            .onChange(of: telemetry?.snapshot) {
                engineSound.receive(readout, receivedAt: rpmReceivedAt)
            }
            .onChange(of: session?.connection.state) {
                engineSound.receive(readout, receivedAt: rpmReceivedAt)
            }
            .onDisappear { try? engineSound.setLifecycle(isDriveVisible: false, isAppActive: false) }
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

    private func configureSound(readout: DriveReadout, receivedAt: ContinuousClock.Instant?) {
        do {
            try engineSound.setLifecycle(isDriveVisible: true, isAppActive: scenePhase == .active)
            try engineSound.configure(.init(isEnabled: soundEnabled, lowersOtherAudio: lowersOtherAudio))
            engineSound.receive(readout, receivedAt: receivedAt)
        } catch {
            Logger(subsystem: "CANCompanion", category: "DriveSound")
                .error("Engine sound could not start: \(error.localizedDescription, privacy: .public)")
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

    var next: DriveStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
