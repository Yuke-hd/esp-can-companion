import SwiftUI
import DesignSystem
import BLETransport
import CompanionLink
import PresetSync

/// The Home ("Pit Wall") screen: the link, the controller, its active config,
/// and entry points to the next features.
struct HomeView: View {
    var model: AppModel
    /// Presets is pushed by state, not by a link inside the cards, so it
    /// stays open while the controller restarts and the link drops.
    @State private var showingPresets = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    header
                    if let session = model.session {
                        ConnectionCard(connection: session.connection)
                        ControllerCard(session: session)
                        if session.phase == .ready, let active = session.activeConfig {
                            ActiveConfigCard(config: active)
                        }
                    } else {
                        BluetoothPermissionCard { model.allowBluetooth() }
                    }
                    EntryPointsSection(openPresets: model.session?.phase == .ready ? { showingPresets = true } : nil)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showingPresets) {
                if let session = model.session {
                    PresetsView(link: session)
                }
            }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Components") { ComponentCatalog() }
                }
            }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(controllerName).themeLabel(Theme.Colors.textSecondary)
                Text("PIT WALL")
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if let connection = model.session?.connection {
                StatusPill(connection.state.title, status: connection.state.pillStatus)
            } else {
                StatusPill("Setup", status: .neutral)
            }
        }
    }

    private var controllerName: String {
        guard let connection = model.session?.connection else { return "No controller" }
        if case .connected(let device) = connection.state, let name = device.name {
            return name
        }
        return connection.rememberedDeviceID == nil ? "No controller" : "Controller"
    }
}

// MARK: - Previews

@MainActor
private func homePreview(_ scenario: DemoScenario) -> some View {
    HomeView(model: AppModel(session: scenario.makeSession()))
        .preferredColorScheme(.dark)
}

#Preview("Not paired") { homePreview(.notPaired) }
#Preview("Connecting") { homePreview(.connecting) }
#Preview("Connected") { homePreview(.connected) }
#Preview("Custom config") { homePreview(.customConfig) }
#Preview("Relinking") { homePreview(.relinking) }
#Preview("Incompatible") { homePreview(.incompatible) }
#Preview("Bluetooth off") { homePreview(.bluetoothOff) }
#Preview("No Bluetooth access") { homePreview(.noAccess) }

#Preview("First launch") {
    HomeView(model: AppModel(deferring: { DemoScenario.notPaired.makeSession() }))
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    homePreview(.connected)
        .environment(\.dynamicTypeSize, .accessibility3)
}
