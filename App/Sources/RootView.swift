import SwiftUI
import DesignSystem
import CompanionLink

/// The four sections from the drafts' bottom bar.
enum AppTab: Int, CaseIterable, Identifiable {
    case pitWall = 1, setup, strip, drive

    var id: Int { rawValue }

    var number: String { String(format: "%02d", rawValue) }

    var title: String {
        switch self {
        case .pitWall: "Pit Wall"
        case .setup: "Setup"
        case .strip: "Strip"
        case .drive: "Drive"
        }
    }
}

/// The app's root: one screen per tab, switched by the drafts' numbered bar.
///
/// A `TabView` keeps each tab alive while another is shown, so Setup keeps
/// a sync in progress when the user looks at the Pit Wall. Its own bar is
/// hidden in favor of `PitTabBar`.
struct RootView: View {
    var model: AppModel
    @State private var selection: AppTab = .pitWall

    var body: some View {
        TabView(selection: $selection) {
            PitWallView(model: model)
                .tag(AppTab.pitWall)
                .toolbar(.hidden, for: .tabBar)
            SetupTab(model: model)
                .tag(AppTab.setup)
                .toolbar(.hidden, for: .tabBar)
            PlaceholderScreen(
                eyebrow: "Track // Zone map",
                title: "Strip",
                message: "The LED strip zone editor comes next. Until then, pick a preset under Setup."
            )
            .tag(AppTab.strip)
            .toolbar(.hidden, for: .tabBar)
            PlaceholderScreen(
                eyebrow: "Drive monitor",
                title: "Drive",
                message: "The landscape drive dashboard comes after the Strip editor. Live values are on the Pit Wall."
            )
            .tag(AppTab.drive)
            .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PitTabBar(selection: $selection)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}

/// The drafts' bottom bar: a number over each title, and a red bar over the
/// selected one.
struct PitTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: Theme.Spacing.xxs) {
                        Rectangle()
                            .fill(isSelected ? Theme.Colors.accent : .clear)
                            .frame(width: 36, height: 3)
                        Text(tab.number)
                            .themeLabel(isSelected ? Theme.Colors.accentText : Theme.Colors.textTertiary)
                        Text(tab.title.uppercased())
                            .font(Theme.Typography.headline)
                            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Theme.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .background(Theme.Colors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Colors.separator).frame(height: 1)
        }
        // Like the system tab bar, the titles stop growing at the largest
        // standard size; four tabs do not fit side by side beyond it.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Setup owns its draft and presents it over the app-wide sync model.
private struct SetupTab: View {
    var model: AppModel
    @State private var selection = SetupSelection()

    var body: some View {
        if let session = model.session, let sync = model.presetSync {
            NavigationStack {
                PresetsView(model: sync, selection: selection,
                            isConnected: session.phase == .ready,
                            isActiveConfigCurrent: model.hasCurrentPresetRead)
            }
        } else {
            PlaceholderScreen(
                eyebrow: "Setup sheet // Presets",
                title: "Setup",
                message: "Allow Bluetooth on the Pit Wall first, then connect to a controller to send presets."
            )
        }
    }
}

/// A tab that has no content yet, in the drafts' header style.
struct PlaceholderScreen: View {
    var eyebrow: String
    var title: String
    var message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ScreenHeader(eyebrow: eyebrow, title: title)
                Card {
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}

/// The drafts' screen header: the red brand mark and a small label over a
/// big italic title, with an optional pill on the right.
struct ScreenHeader<Trailing: View>: View {
    var eyebrow: String
    var title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the pill goes under the title, so neither is cut.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .bottom))
        layout {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    BrandMark()
                    Text(eyebrow)
                        .themeLabel(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Text(title.uppercased())
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: Theme.Spacing.xs)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

/// Three slanted red bars, the drafts' logo mark.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.Colors.accent)
                    .frame(width: 4, height: 10)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.35, d: 1, tx: 3, ty: 0))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Root") {
    RootView(model: AppModel(session: DemoScenario.connected.makeSession()))
        .preferredColorScheme(.dark)
}
