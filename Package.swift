// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookSweep",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NookSweep", targets: ["NookSweep"])],
    targets: [
        .target(name: "NookSweepCore"),
        .executableTarget(name: "NookSweep", dependencies: ["NookSweepCore"]),
        .testTarget(name: "NookSweepCoreTests", dependencies: ["NookSweepCore"])
    ]
)
