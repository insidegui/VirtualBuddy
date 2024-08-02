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
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/insidegui/libfragmentzip", from: "1.0.0")
    ],
    targets: [
        .target(name: "VirtualCatalog"),
        .executableTarget(
            name: "vctool",
            dependencies: [
                .target(name: "VirtualCatalog"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FragmentZip", package: "libfragmentzip")
            ],
            linkerSettings: [
                .linkedLibrary("curl"),
                .linkedLibrary("z"),
            ]
        )
    ]
)
