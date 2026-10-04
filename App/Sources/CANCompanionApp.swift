import SwiftUI
import DesignSystem

@main
struct CANCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
        }
    }
}
