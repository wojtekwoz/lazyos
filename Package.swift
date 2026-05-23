// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LazyOS",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LazyOSCore", targets: ["LazyOSCore"]),
        .executable(name: "lazyos", targets: ["lazyos"]),
        .executable(name: "LazyOSApp", targets: ["LazyOSApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "LazyOSCore",
            path: "Sources/LazyOSCore",
            resources: [.copy("Catalog/Templates")]
        ),
        .executableTarget(
            name: "lazyos",
            dependencies: [
                "LazyOSCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/lazyos"
        ),
        .executableTarget(
            name: "LazyOSApp",
            dependencies: ["LazyOSCore"],
            path: "Sources/LazyOSApp"
        ),
        .testTarget(
            name: "LazyOSCoreTests",
            dependencies: ["LazyOSCore"],
            path: "Tests/LazyOSCoreTests"
        ),
    ]
)
