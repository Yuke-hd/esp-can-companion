import SwiftUI
import DesignSystem
import BLETransport

/// Placeholder Home ("Pit Wall") screen. The real screen lands with the BLE manager and protocol client.
struct HomeView: View {
    var linkState: LinkState = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("No controller").themeLabel(Theme.Colors.textSecondary)
                            Text("PIT WALL")
                                .font(Theme.Typography.display)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Spacer()
                        StatusPill(linkState.title, status: linkState.pillStatus)
                    }

                    Card(edge: Theme.Colors.accent) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Controller").themeLabel()
                            Text("Not paired")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Bluetooth support is coming next.")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    Button("Connect") {}
                        .buttonStyle(.primary)
                        .disabled(true)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Components") { ComponentCatalog() }
                }
            }
            #endif
        }
    }
}

extension LinkState {
    var title: String {
        switch self {
        case .idle: "Not linked"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .connected: "Linked"
        case .disconnected: "Lost link"
        }
    }

    var pillStatus: StatusPill.Status {
        switch self {
        case .idle: .neutral
        case .scanning, .connecting: .pending
        case .connected: .live
        case .disconnected: .alert
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
