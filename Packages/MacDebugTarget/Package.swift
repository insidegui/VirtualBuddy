// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDebugTarget",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacDebugTarget", targets: ["MacDebugTarget"])],
    dependencies: [.package(path: "../MacDebugProtocol")],
    targets: [
        .target(name: "MacDebugTarget", dependencies: ["MacDebugProtocol"]),
        .testTarget(name: "MacDebugTargetTests", dependencies: ["MacDebugTarget"])
    ]
)
