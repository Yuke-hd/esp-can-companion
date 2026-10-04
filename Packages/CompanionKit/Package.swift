// swift-tools-version:5.9
import PackageDescription

// Module layout:
//  - BLETransport:      CoreBluetooth connection and framing (no protocol knowledge).
//  - CompanionProtocol: message types and codecs for the companion BLE protocol (no UI, no CoreBluetooth).
//  - CompanionLink:     runs the protocol client over the connection manager and
//                       keeps the controller's state for the UI (no SwiftUI).
//  - PresetSync:        bundled presets and the push / revert flow (no UI, no CoreBluetooth).
//  - CompanionFakes:    in-memory controller for tests and previews.
//  - DesignSystem:      dark theme tokens and shared SwiftUI components.
let package = Package(
    name: "CompanionKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BLETransport", targets: ["BLETransport"]),
        .library(name: "CompanionProtocol", targets: ["CompanionProtocol"]),
        .library(name: "CompanionLink", targets: ["CompanionLink"]),
        .library(name: "PresetSync", targets: ["PresetSync"]),
        .library(name: "CompanionFakes", targets: ["CompanionFakes"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "BLETransport"),
        .target(name: "CompanionProtocol"),
        .target(name: "CompanionLink", dependencies: ["BLETransport", "CompanionProtocol", "PresetSync"]),
        .target(
            name: "PresetSync",
            dependencies: ["CompanionProtocol"],
            resources: [.copy("Presets")]
        ),
        .target(name: "CompanionFakes", dependencies: ["CompanionProtocol", "PresetSync"]),
        .target(name: "DesignSystem"),
        .testTarget(name: "BLETransportTests", dependencies: ["BLETransport"]),
        .testTarget(
            name: "CompanionProtocolTests",
            dependencies: ["CompanionProtocol", "CompanionFakes"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CompanionLinkTests", dependencies: ["CompanionLink"]),
        .testTarget(
            name: "PresetSyncTests",
            dependencies: ["PresetSync", "CompanionFakes"]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ]
)
