// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EngineSim",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EngineSim", targets: ["EngineSimCore"]),
        // A second product makes SwiftPM expose the `EngineSim-Package` scheme that
        // CI and the issue's verification commands use.
        .library(name: "EngineSimCore", targets: ["EngineSimCore"]),
    ],
    targets: [
        .target(
            name: "EngineSimCore",
            exclude: [
                "compat/backslash-includes",
                "upstream/engine-sim/LICENSE",
                "upstream/engine-sim/dependencies/submodules/simple-2d-constraint-solver/LICENSE",
            ],
            cxxSettings: [
                .headerSearchPath("compat/include"),
                .headerSearchPath("compat/backslash-includes"),
                .headerSearchPath("upstream/engine-sim/include"),
                .define("__forceinline", to: "inline"),
                // Upstream guards two asserts with identifiers that only compile
                // when asserts are off (piston_engine_simulator.cpp).
                .define("NDEBUG"),
                // Upstream templates rely on MSVC-style delayed template parsing.
                .unsafeFlags(["-fdelayed-template-parsing", "-O2"]),
            ],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .testTarget(
            name: "EngineSimCoreTests",
            dependencies: ["EngineSimCore"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
