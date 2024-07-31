// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VirtualCatalog",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "VirtualCatalog",
            targets: ["VirtualCatalog"]),
    ],
    targets: [
        .target(name: "VirtualCatalog"),
    ]
)
