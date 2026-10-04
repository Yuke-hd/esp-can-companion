import SwiftUI
import DesignSystem
import BLETransport

/// Placeholder Home ("Pit Wall") screen. The real screen lands with #4; this one
/// shows the link state and enough controls to scan, connect, and disconnect.
struct HomeView: View {
    var connection: ConnectionManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(controllerName).themeLabel(Theme.Colors.textSecondary)
                            Text("PIT WALL")
                                .font(Theme.Typography.display)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Spacer()
                        StatusPill(connection.state.title, status: connection.state.pillStatus)
                    }

                    Card(edge: Theme.Colors.accent) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Controller").themeLabel()
                            Text(connection.state.headline)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(connection.state.detail)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    if connection.state == .scanning {
                        ForEach(connection.discoveredDevices) { device in
                            Button {
                                connection.connect(to: device.id)
                            } label: {
                                Card {
                                    HStack {
                                        Text(device.name ?? "Unnamed controller")
                                            .font(Theme.Typography.headline)
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                        Spacer()
                                        Text("\(device.rssi) dBm").themeLabel(Theme.Colors.textSecondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    primaryAction
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Components") { ComponentCatalog() }
                }
            }
            #endif
        }
    }

    private var controllerName: String {
        if case .connected(let device) = connection.state, let name = device.name {
            return name
        }
        return connection.rememberedDeviceID == nil ? "No controller" : "Controller"
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch connection.state {
        case .connected, .connecting, .pairing, .disconnected(_, willReconnect: true):
            Button("Disconnect") { connection.disconnect() }
                .buttonStyle(.secondary)
        case .scanning:
            Button("Stop scanning") { connection.stopScan() }
                .buttonStyle(.secondary)
        case .idle, .disconnected:
            Button("Connect") {
                if connection.rememberedDeviceID != nil {
                    connection.reconnect()
                } else {
                    connection.startScan()
                }
            }
            .buttonStyle(.primary)
            if connection.rememberedDeviceID != nil {
                Button("Forget controller") { connection.forgetDevice() }
                    .buttonStyle(.secondary)
            }
        case .unknown, .unsupported, .unauthorized, .poweredOff:
            Button("Connect") {}
                .buttonStyle(.primary)
                .disabled(true)
        }
    }
}

extension LinkState {
    var title: String {
        switch self {
        case .unknown: "Starting"
        case .unsupported: "No Bluetooth"
        case .unauthorized: "No access"
        case .poweredOff: "Bluetooth off"
        case .idle: "Not linked"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .pairing: "Pairing"
        case .connected: "Linked"
        case .disconnected(_, let willReconnect): willReconnect ? "Relinking" : "Lost link"
        }
    }

    var headline: String {
        switch self {
        case .connected: "Paired"
        case .pairing: "Pairing"
        default: "Not paired"
        }
    }

    var detail: String {
        switch self {
        case .unknown: "Checking Bluetooth."
        case .unsupported: "This device does not support Bluetooth LE."
        case .unauthorized: "Allow Bluetooth access in Settings to talk to the controller."
        case .poweredOff: "Turn on Bluetooth to connect."
        case .idle: "No controller paired yet."
        case .scanning: "Looking for controllers nearby."
        case .connecting: "Waiting for the controller. It connects as soon as it is in range."
        case .pairing: "Pairing with the controller."
        case .connected(let device): "Connected to \(device.name ?? "the controller")."
        case .disconnected(let reason, _):
            switch reason {
            case .userRequested: "Disconnected."
            case .connectionLost: "Lost the connection. Waiting for the controller to come back."
            case .connectFailed: "Could not connect. Retrying."
            case .pairingFailed: "Pairing did not complete. Try again."
            case .bondRemoved: "The controller forgot this phone. Forget it in iOS Settings > Bluetooth, then pair again."
            case .incompatibleDevice: "This device is not a companion controller."
            }
        }
    }

    var pillStatus: StatusPill.Status {
        switch self {
        case .idle, .unknown: .neutral
        case .scanning, .connecting, .pairing: .pending
        case .connected: .live
        case .disconnected(_, let willReconnect): willReconnect ? .pending : .alert
        case .unsupported, .unauthorized, .poweredOff: .alert
        }
    }
}

#Preview {
    HomeView(connection: .demo())
        .preferredColorScheme(.dark)
}
