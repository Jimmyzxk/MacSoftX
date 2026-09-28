// swift-tools-version: 5.9
// 最低 Swift 工具链 5.9（Xcode 15），保证多数 macOS 15/26 环境可直接构建
// TODO(swift-6): 迁移至 Swift 6 strict concurrency

import PackageDescription

let package = Package(
    name: "upmac",
    platforms: [
        // 5.9 工具链尚无 .v15 常量，使用字符串形式的自定义平台版本声明
        .macOS("15.0")
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
    ]
)
