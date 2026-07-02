// swift-tools-version: 5.10
// SweepCore: the platform-agnostic core (engine, bundle reader, curb snapper,
// persistence, notification planning). The iOS app + widget targets are wired
// by XcodeGen (project.yml) and depend on this local package; keeping the core
// here lets `swift test` run the full §13 suite on macOS with no simulator.
import PackageDescription

let package = Package(
    name: "SweepCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SweepCore", targets: ["SweepCore"]),
    ],
    targets: [
        .target(
            name: "SweepCore",
            path: "Sweep/Core"
        ),
        .testTarget(
            name: "SweepCoreTests",
            dependencies: ["SweepCore"],
            path: "SweepTests/Core",
            resources: [.copy("Fixtures")]
        ),
    ]
)
