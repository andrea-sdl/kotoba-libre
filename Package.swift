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
            // Shared resources are listed explicitly so unused artwork can stay in the repo without bloating the app bundle.
            resources: [
                .process("Resources/AboutArtworkLoop.mp4"),
                .process("Resources/AppIcon.icns"),
                .process("Resources/AppIcon.png"),
                .process("Resources/OnboardingArtwork.png")
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
