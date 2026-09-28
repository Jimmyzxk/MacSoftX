// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
// TODO(swift-6): 迁移至 Swift 6 strict concurrency

import PackageDescription

let package = Package(
    name: "upmac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "upmac",
            targets: ["upmac"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "upmac",
            dependencies: [],
            path: "Sources/upmac"
        ),
        .testTarget(
            name: "upmacTests",
            dependencies: ["upmac"],
            path: "Tests/upmacTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
