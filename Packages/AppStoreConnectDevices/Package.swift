// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppStoreConnectDevices",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppStoreConnectDevices", targets: ["AppStoreConnectDevices"])],
    targets: [
        .target(name: "AppStoreConnectDevices"),
        .testTarget(name: "AppStoreConnectDevicesTests", dependencies: ["AppStoreConnectDevices"])
    ]
)
