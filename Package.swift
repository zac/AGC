// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AGC",
    platforms: [
        .iOS("17.0"),
        .macOS("14.0"),
        .watchOS("10.0"),
        .tvOS("17.0"),
        .visionOS("1.0")
    ],
    products: [
        .library(
            name: "AGC",
            targets: ["AGC"]),
        .library(
            name: "LMCore",
            targets: ["LMCore"]),
    ],
    targets: [
        .target(
            name: "AGC"
        ),
        .target(
            name: "LMCore",
            dependencies: ["AGC"]
        ),
        .testTarget(
            name: "AGCTests",
            dependencies: ["AGC"],
            resources: [
                .copy("Luminary099.bin"),
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "LMCoreTests",
            dependencies: ["AGC", "LMCore"]
        ),
    ]
)
