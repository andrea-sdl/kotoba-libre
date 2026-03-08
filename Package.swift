// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KotobaLibre",
    platforms: [
        .macOS(.v13)
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
