// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SharedKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SharedKit", targets: ["SharedKit"]),
    ],
    targets: [
        .target(name: "SharedKit"),
        .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"]),
    ]
)
