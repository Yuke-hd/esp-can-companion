import SwiftUI
import DesignSystem
import CompanionLink

/// A catalog-backed list with no subscription or connection ownership.
struct DiscoveredSignalsView: View {
    enum State: Equatable {
        case loading, ready, empty, unavailable, disconnected, stalled

        var title: String {
            switch self {
            case .loading: "Discovering signals"
            case .ready: "Discovered signals"
            case .empty: "No discovered signals"
            case .unavailable: "Telemetry unavailable"
            case .disconnected: "Controller disconnected"
            case .stalled: "Telemetry stalled"
            }
        }

        var detail: String {
            switch self {
            case .loading: "Waiting for a complete signal catalog."
            case .ready: "Read-only values and metadata advertised by this controller. Unit and evidence tokens are shown without interpretation."
            case .empty: "The controller's catalog contains no signals."
            case .unavailable: "A usable signal catalog and stream are required."
            case .disconnected: "Reconnect to discover the controller's current signals."
            case .stalled: "No recent packets. Obsolete values have been cleared."
            }
        }
    }

    var rows: [SignalReadout.Row]
    var state: State
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(state.title).font(Theme.Typography.headline)
                        Text(state.detail).font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("signals.state")
                    ForEach(rows) { row in
                        Card {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(row.key).font(Theme.Typography.headline)
                                Text(row.value ?? "—").font(Theme.Typography.value)
                                Text("\(row.type) · \(row.status.title)")
                                    .font(Theme.Typography.body)
                                Text("Unit token: \(row.unit)")
                                Text("Evidence token: \(row.evidence)")
                                if !row.choices.isEmpty {
                                    Text("Choices: " + row.choices.joined(separator: ", "))
                                }
                            }
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.accessibilityText)
                        .accessibilityIdentifier(row.accessibilityIdentifier)
                    }
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md)
            }
            .accessibilityIdentifier("signals.list")
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Discovered signals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("signals.close")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
