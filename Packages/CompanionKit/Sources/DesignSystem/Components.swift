import SwiftUI

/// A flat surface that groups related content, with an optional colored edge
/// (the drafts use a red edge on the controller summary card).
public struct Card<Content: View>: View {
    private let edge: Color?
    private let content: Content

    public init(edge: Color? = nil, @ViewBuilder content: () -> Content) {
        self.edge = edge
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(alignment: .leading) {
                if let edge {
                    Rectangle().fill(edge).frame(width: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }
}

/// A small outlined tag showing a state such as "LINKED", "3 CHANGES", or "EDITING".
public struct StatusPill: View {
    public enum Status: Sendable {
        case neutral, live, pending, editing, alert

        /// Saturated color for the dot, border, and fill.
        public var tint: ColorToken {
            switch self {
            case .neutral: Theme.Palette.textSecondary
            case .live: Theme.Palette.signalTeal
            case .pending: Theme.Palette.signalYellow
            case .editing: Theme.Palette.signalBlue
            case .alert: Theme.Palette.accent
            }
        }

        /// Label color, lighter where the saturated tint is too dark for 11 pt text.
        public var text: ColorToken {
            switch self {
            case .editing: Theme.Palette.signalBlueText
            case .alert: Theme.Palette.accentText
            default: tint
            }
        }
    }

    /// Opacity of the tint fill behind the label.
    static let fillOpacity = 0.1

    private let title: String
    private let status: Status

    public init(_ title: String, status: Status) {
        self.title = title
        self.status = status
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs - 2) {
            Circle()
                .fill(status.tint.color)
                .frame(width: 6, height: 6)
            Text(title)
                .themeLabel(status.text.color)
        }
        .padding(.horizontal, Theme.Spacing.xs + 2)
        .padding(.vertical, Theme.Spacing.xs - 2)
        .background(status.tint.color.opacity(Self.fillOpacity))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xs)
                .strokeBorder(status.tint.color.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Filled red button for the main action on a screen, such as "SEND TO CAR".
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textOnAccent)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.xs))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined button for a secondary action next to a primary one, such as "PREVIEW".
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? Theme.Colors.surfaceRaised : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xs)
                    .strokeBorder(Theme.Colors.textSecondary, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
