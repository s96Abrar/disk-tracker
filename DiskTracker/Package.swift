// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DiskTracker",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "DiskTracker",
            targets: ["DiskTracker"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "DiskTracker",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
