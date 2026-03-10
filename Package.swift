// swift-tools-version: 6.2

import PackageDescription

// This manifest describes the desktop app, the shared core module,
// and the executable self-test suite.
let package = Package(
    name: "KotobaLibre",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "KotobaLibreCore",
            targets: ["KotobaLibreCore"]
        ),
        .executable(
            name: "KotobaLibreApp",
            targets: ["KotobaLibreApp"]
        ),
        .executable(
            name: "KotobaLibreSelfTest",
            targets: ["KotobaLibreSelfTest"]
        )
    ],
    targets: [
        .target(
            name: "KotobaLibreCore",
            // Shared resources live with the core target so both the app and tests can find them.
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "KotobaLibreApp",
            dependencies: ["KotobaLibreCore"]
        ),
        .executableTarget(
            name: "KotobaLibreSelfTest",
            dependencies: ["KotobaLibreCore"],
        )
    ]
)
