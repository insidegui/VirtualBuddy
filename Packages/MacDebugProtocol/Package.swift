// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDebugProtocol",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacDebugProtocol", targets: ["MacDebugProtocol"])],
    targets: [
        .target(name: "MacDebugProtocol"),
        .testTarget(name: "MacDebugProtocolTests", dependencies: ["MacDebugProtocol"])
    ]
)
