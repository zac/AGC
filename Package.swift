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
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AGC",
            targets: ["AGC"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AGC"
        ),
        .testTarget(
            name: "AGCTests",
            dependencies: ["AGC"],
            resources: [
                .process("../Luminary099.bin")
            ]
        ),
    ]
)
