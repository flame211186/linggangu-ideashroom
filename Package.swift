// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LingGanGu",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LingGanGuCore", targets: ["LingGanGuCore"]),
        .executable(name: "LingGanGuCoreChecks", targets: ["LingGanGuCoreChecks"]),
        .executable(name: "LingGanGu", targets: ["LingGanGuApp"])
    ],
    targets: [
        .target(
            name: "LingGanGuCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "LingGanGuCoreChecks",
            dependencies: ["LingGanGuCore"]
        ),
        .executableTarget(
            name: "LingGanGuApp",
            dependencies: ["LingGanGuCore"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("SpriteKit")
            ]
        ),
        .testTarget(
            name: "LingGanGuCoreTests",
            dependencies: ["LingGanGuCore"]
        )
    ]
)
