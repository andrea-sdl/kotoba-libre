// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ToroLibre",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ToroLibreCore",
            targets: ["ToroLibreCore"]
        ),
        .executable(
            name: "ToroLibreApp",
            targets: ["ToroLibreApp"]
        ),
        .executable(
            name: "ToroLibreSelfTest",
            targets: ["ToroLibreSelfTest"]
        )
    ],
    targets: [
        .target(
            name: "ToroLibreCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ToroLibreApp",
            dependencies: ["ToroLibreCore"]
        ),
        .executableTarget(
            name: "ToroLibreSelfTest",
            dependencies: ["ToroLibreCore"],
        )
    ]
)
