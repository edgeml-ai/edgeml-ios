// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EdgeML",
    platforms: [
        .iOS(.v15),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "EdgeML",
            targets: ["EdgeML"]
        ),
        .library(
            name: "EdgeMLClip",
            targets: ["EdgeMLClip"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EdgeML",
            dependencies: [],
            path: "Sources/EdgeML"
        ),
        .target(
            name: "EdgeMLClip",
            dependencies: ["EdgeML"],
            path: "Sources/EdgeMLClip"
        ),
        .testTarget(
            name: "EdgeMLTests",
            dependencies: ["EdgeML"],
            path: "Tests/EdgeMLTests"
        ),
    ]
)
