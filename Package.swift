// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EdgeML",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "EdgeML",
            targets: ["EdgeML"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EdgeML",
            dependencies: [],
            path: "Sources/EdgeML"
        ),
        .testTarget(
            name: "EdgeMLTests",
            dependencies: ["EdgeML"],
            path: "Tests/EdgeMLTests"
        ),
    ]
)
