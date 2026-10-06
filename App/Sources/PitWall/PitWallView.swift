import SwiftUI
import DesignSystem
import BLETransport
import CompanionProtocol
import CompanionLink

/// The Pit Wall, as in the drafts: the controller at a glance, live
/// telemetry, signal tiles and the output stack. Until a controller is ready
/// it shows how to connect instead.
struct PitWallView: View {
    var model: AppModel
    var isLive = true
    @State private var showingConnection = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ScreenHeader(eyebrow: eyebrow, title: "Pit Wall") {
                        linkPill
                    }
                    if let session = model.session {
                        if session.phase == .ready, isLive {
                            PitWallLive(session: session)
                        } else if session.phase != .ready {
                            ConnectionCard(connection: session.connection)
                            ControllerCard(session: session)
                        }
                    } else {
                        BluetoothPermissionCard { model.allowBluetooth() }
                    }
                    #if DEBUG
                    NavigationLink("Components") { ComponentCatalog() }
                        .themeLabel(Theme.Colors.textSecondary)
                        .padding(.top, Theme.Spacing.sm)
                    #endif
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingConnection) {
                if let session = model.session {
                    ConnectionSheet(session: session)
                }
            }
        }
    }

    @ViewBuilder
    private var linkPill: some View {
        if let connection = model.session?.connection {
            Button {
                showingConnection = true
            } label: {
                StatusPill(connection.state.title, status: connection.state.pillStatus)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link, \(connection.state.title)")
            .accessibilityHint("Shows connection details")
        } else {
            StatusPill("Setup", status: .neutral)
        }
    }

    /// "DEMO CONTROLLER // WEACT-CAN485-V1.1", like the drafts' "KF CX-5 // ESP32".
    private var eyebrow: String {
        guard let session = model.session else { return "No controller" }
        var parts: [String] = []
        if case .connected(let device) = session.connection.state {
            parts.append(device.name ?? "Controller")
        } else {
            parts.append(session.connection.rememberedDeviceID == nil ? "No controller" : "Controller")
        }
        if let hardware = session.deviceInfo?.hardwareID {
            parts.append(hardware)
        }
        return parts.joined(separator: " // ")
    }
}

/// The ready Pit Wall. Owns the Live signals subscription, which runs only
/// while this view is on screen.
private struct PitWallLive: View {
    var session: ControllerSession
    @State private var telemetry: LiveTelemetry

    init(session: ControllerSession) {
        self.session = session
        _telemetry = State(initialValue: LiveTelemetry(session: session))
    }

    var body: some View {
        let summary = session.activeConfig?.configSummary
        let readout = PitWallReadout(frame: telemetry.frame, band: AppConfig.default.rpmBand)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ControllerStrip(
                firmware: session.deviceInfo?.firmwareVersion,
                profile: session.activeConfig?.profileTitle,
                bus: readout.busTitle
            )
            TelemetryCard(readout: readout, framesPerSecond: telemetry.framesPerSecond, failure: telemetry.failure)
            SignalTileGrid(tiles: readout.tiles)
            if let summary {
                OutputStackCard(outputs: summary.outputStack)
            }
        }
        .task { await telemetry.run() }
    }
}

/// Connection, controller and the active config in full, opened from the
/// link pill.
private struct ConnectionSheet: View {
    var session: ControllerSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ConnectionCard(connection: session.connection)
                    ControllerCard(session: session)
                    if session.phase == .ready, let active = session.activeConfig {
                        ActiveConfigCard(config: active)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Previews

@MainActor
private func pitWallPreview(_ scenario: DemoScenario) -> some View {
    PitWallView(model: AppModel(session: scenario.makeSession()))
        .preferredColorScheme(.dark)
}

#Preview("Connected") { pitWallPreview(.connected) }
#Preview("Custom config") { pitWallPreview(.customConfig) }
#Preview("Not paired") { pitWallPreview(.notPaired) }
#Preview("Connecting") { pitWallPreview(.connecting) }
#Preview("Relinking") { pitWallPreview(.relinking) }
#Preview("Incompatible") { pitWallPreview(.incompatible) }
#Preview("Bluetooth off") { pitWallPreview(.bluetoothOff) }
#Preview("No Bluetooth access") { pitWallPreview(.noAccess) }

#Preview("First launch") {
    PitWallView(model: AppModel(deferring: { DemoScenario.notPaired.makeSession() }))
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    pitWallPreview(.connected)
        .environment(\.dynamicTypeSize, .accessibility3)
}
