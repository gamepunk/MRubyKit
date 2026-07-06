// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "MRubyKit",
    platforms: [
        .macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1),
    ],
    products: [
        .library(name: "MRubyKit", targets: ["MRubyKit"]),
    ],
    targets: [
        // mruby 4.0.0 预编译静态库（Apple 全平台 XCFramework）
        // 由 scripts/build.sh 生成
        .binaryTarget(
            name: "MRuby",
            path: "build/MRuby.xcframework"
        ),

        // C 桥接层：
        //   - 汇总 mruby 公开头文件（shim.h）
        //   - 将 Swift 无法调用的函数式宏包装为普通 C 内联函数
        .target(
            name: "CMRuby",
            dependencies: ["MRuby"],
            path: "Sources/CMRuby",
            publicHeadersPath: "include"
        ),

        // Swift 封装层
        .target(
            name: "MRubyKit",
            dependencies: ["CMRuby"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),

        .testTarget(
            name: "MRubyKitTests",
            dependencies: ["MRubyKit"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
