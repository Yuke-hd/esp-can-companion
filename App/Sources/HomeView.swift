import SwiftUI
import DesignSystem
import BLETransport

/// Placeholder Home screen. The real screen lands with the BLE manager and protocol client.
struct HomeView: View {
    var linkState: LinkState = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("Controller")
                                    .font(Theme.Typography.headline)
                                Spacer()
                                StatusPill(linkState.title, status: linkState.pillStatus)
                            }
                            Text("No controller paired yet. Bluetooth support is coming next.")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Button("Connect") {}
                        .buttonStyle(.primary)
                        .disabled(true)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Home")
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
        case .idle: "Not connected"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        }
    }

    var pillStatus: StatusPill.Status {
        switch self {
        case .idle: .neutral
        case .scanning, .connecting: .warning
        case .connected: .success
        case .disconnected: .danger
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
