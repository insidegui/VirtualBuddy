// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDebugHost",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacDebugHost", targets: ["MacDebugHost"])],
    dependencies: [.package(path: "../MacDebugProtocol")],
    targets: [
        .target(name: "MacDebugHost", dependencies: ["MacDebugProtocol"], resources: [.copy("Resources/mac_debug.py")]),
        .testTarget(name: "MacDebugHostTests", dependencies: ["MacDebugHost"])
    ]
)
