// swift-tools-version:5.9
import PackageDescription

// Module layout:
//  - BLETransport:      CoreBluetooth connection and framing (no protocol knowledge).
//  - CompanionProtocol: message types and codecs for the companion BLE protocol (no UI, no CoreBluetooth).
//  - CompanionLink:     runs the protocol client over the connection manager and
//                       keeps the controller's state for the UI (no SwiftUI).
//  - DesignSystem:      dark theme tokens and shared SwiftUI components.
let package = Package(
    name: "CompanionKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BLETransport", targets: ["BLETransport"]),
        .library(name: "CompanionProtocol", targets: ["CompanionProtocol"]),
        .library(name: "CompanionLink", targets: ["CompanionLink"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "BLETransport"),
        .target(name: "CompanionProtocol"),
        .target(name: "CompanionLink", dependencies: ["BLETransport", "CompanionProtocol"]),
        .target(name: "DesignSystem"),
        .testTarget(name: "BLETransportTests", dependencies: ["BLETransport"]),
        .testTarget(
            name: "CompanionProtocolTests",
            dependencies: ["CompanionProtocol"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CompanionLinkTests", dependencies: ["CompanionLink"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ]
)
