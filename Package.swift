// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LetsMoveSwiftly",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "LetsMoveSwiftly",
            targets: ["LetsMoveSwiftly"]
        ),
    ],
    targets: [
        .target(
            name: "LetsMoveSwiftly",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "LetsMoveSwiftlyTests",
            dependencies: ["LetsMoveSwiftly"]
        ),
    ]
)
