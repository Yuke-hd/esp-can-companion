import SwiftUI

/// A rounded surface that groups related content.
public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.Colors.separator, lineWidth: 1)
            )
    }
}

/// A small capsule showing a state such as "Connected" or "Offline".
public struct StatusPill: View {
    public enum Status: Sendable {
        case neutral, success, warning, danger

        var tint: Color {
            switch self {
            case .neutral: Theme.Colors.textSecondary
            case .success: Theme.Colors.success
            case .warning: Theme.Colors.warning
            case .danger: Theme.Colors.danger
            }
        }
    }

    private let title: String
    private let status: Status

    public init(_ title: String, status: Status) {
        self.title = title
        self.status = status
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(status.tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs + 2)
        .background(status.tint.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Full-width filled button style for the main action on a screen.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.textOnAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
