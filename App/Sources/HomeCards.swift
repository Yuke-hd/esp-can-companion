import SwiftUI
import UIKit
import DesignSystem
import BLETransport
import CompanionProtocol
import CompanionLink

// MARK: - Connection

/// The link: its state, the device, and what the user can do about it.
struct ConnectionCard: View {
    var connection: ConnectionManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card(edge: Theme.Colors.accent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Connection").themeLabel()
                    Text(connection.state.title)
                        .font(Theme.Typography.value)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let deviceName {
                        Text(deviceName)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text(connection.state.detail)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                if connection.state == .scanning {
                    discoveredDevices
                }
                actions
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connection")
    }

    private var deviceName: String? {
        if case .connected(let device) = connection.state {
            return device.name ?? "Unnamed controller"
        }
        return nil
    }

    @ViewBuilder
    private var discoveredDevices: some View {
        if connection.discoveredDevices.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView()
                Text("Searching").themeLabel(Theme.Colors.textSecondary)
            }
        }
        ForEach(connection.discoveredDevices) { device in
            Button {
                connection.connect(to: device.id)
            } label: {
                HStack {
                    Text(device.name ?? "Unnamed controller")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text("\(device.rssi) dBm").themeLabel(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.xs))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect to \(device.name ?? "unnamed controller")")
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch connection.state {
        case .connected, .connecting, .pairing, .disconnected(_, willReconnect: true):
            Button("Disconnect") { connection.disconnect() }
                .buttonStyle(.secondary)
        case .scanning:
            Button("Stop scanning") { connection.stopScan() }
                .buttonStyle(.secondary)
        case .idle, .disconnected:
            if connection.rememberedDeviceID != nil {
                Button("Reconnect") { connection.reconnect() }
                    .buttonStyle(.primary)
                Button("Forget controller") { connection.forgetDevice() }
                    .buttonStyle(.secondary)
            } else {
                Button("Find a controller") { connection.startScan() }
                    .buttonStyle(.primary)
            }
        case .unauthorized:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.primary)
        case .unknown, .unsupported, .poweredOff:
            EmptyView()
        }
    }
}

// MARK: - Bluetooth permission

/// Shown on first launch, before iOS asks for Bluetooth access.
struct BluetoothPermissionCard: View {
    var allow: @MainActor () -> Void

    var body: some View {
        Card(edge: Theme.Colors.accent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Bluetooth").themeLabel()
                    Text("Allow Bluetooth")
                        .font(Theme.Typography.value)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("CAN Companion talks to your accessory controller over Bluetooth. iOS will ask you to allow it.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Button("Continue") { allow() }
                    .buttonStyle(.primary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bluetooth permission")
    }
}

// MARK: - Controller

/// Firmware, protocol, and which config is active.
struct ControllerCard: View {
    var session: ControllerSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Controller").themeLabel()
                    .accessibilityHidden(true)
                if session.phase == .ready, let info = session.deviceInfo, let status = session.configStatus {
                    details(info: info, status: status)
                } else if let message = session.phase.message(for: session.connection.state) {
                    placeholder(message)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controller")
    }

    private func details(info: DeviceInfo, status: ConfigStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            let fields = Group {
                field("Firmware", info.firmwareVersion, Theme.Colors.textPrimary)
                field("Protocol", info.protocolText, Theme.Colors.textPrimary)
                field("Config", status.activeSource.title, status.activeSource == .known(.persistedOverride)
                    ? Theme.Colors.signalBlueText : Theme.Colors.signalTeal)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) { fields }
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.md) { fields }
            }
            Text(info.hardwareID).themeLabel(Theme.Colors.textSecondary)
                .accessibilityLabel("Hardware \(info.hardwareID)")
            if info.compatibility().hasNewerMinor {
                note("This controller has newer protocol features that this app ignores.", Theme.Colors.textSecondary)
            }
            ForEach(status.bootWarnings, id: \.self) { warning in
                note(warning, Theme.Colors.signalYellow)
            }
        }
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if session.phase == .loading { ProgressView() }
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        if case .failed = session.phase {
            Button("Try again") { session.reload() }
                .buttonStyle(.secondary)
        }
    }

    private func field(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label).themeLabel()
            Text(value).font(Theme.Typography.headline).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Active config

/// Each action of the active config, with its trigger and output in plain language.
struct ActiveConfigCard: View {
    var config: ControllerSession.ActiveConfig

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Active config").themeLabel()
                    .accessibilityHidden(true)
                switch config {
                case .none:
                    message("The controller is not running any config.")
                case .unreadable(let reason):
                    message(reason)
                case .summary(let summary) where summary.actions.isEmpty:
                    message("This config has no actions.")
                case .summary(let summary):
                    ForEach(summary.actions) { action in
                        row(action)
                        if action.id != summary.actions.last?.id {
                            Divider().overlay(Theme.Colors.separator)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active config")
    }

    private func row(_ action: ConfigSummary.Action) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(action.title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            ForEach(action.triggers, id: \.self) { trigger in
                Text(trigger)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(action.outputs, id: \.self) { output in
                Text(output).themeLabel(Theme.Colors.signalTeal)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.accessibilityText)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Entry points

/// Presets and Drive, disabled until those features land.
struct EntryPointsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Coming next").themeLabel()
                .accessibilityAddTraits(.isHeader)
            entry("Presets", detail: "Send a ready-made lighting setup", systemImage: "square.stack.3d.up")
            entry("Drive", detail: "Live signals while you drive", systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    private func entry(_ title: String, detail: String, systemImage: String) -> some View {
        Button {} label: {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: systemImage)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(detail)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text("Soon").themeLabel(Theme.Colors.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.5)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint("Not available yet")
    }
}
