// swift-tools-version:5.9
import PackageDescription

// Module layout:
//  - BLETransport:      CoreBluetooth connection and framing (no protocol knowledge).
//  - CompanionProtocol: message types and codecs for the companion BLE protocol (no UI, no CoreBluetooth).
//  - DesignSystem:      dark theme tokens and shared SwiftUI components.
let package = Package(
    name: "CompanionKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BLETransport", targets: ["BLETransport"]),
        .library(name: "CompanionProtocol", targets: ["CompanionProtocol"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "BLETransport"),
        .target(name: "CompanionProtocol"),
        .target(name: "DesignSystem"),
        .testTarget(name: "CompanionProtocolTests", dependencies: ["CompanionProtocol"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ]
)
