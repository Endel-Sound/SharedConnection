// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SharedConnectionService",
    platforms: [.iOS(.v13), .watchOS(.v6)],
    products: [
        .library(
            name: "SharedConnection",
            targets: ["SharedConnectionService"]),
        .library(
            name: "ReactiveSharedConnection",
            targets: ["ReactiveSharedConnectionService"])
    ],
    dependencies: [
        .package(url: "https://github.com/DeclarativeHub/ReactiveKit.git", from: "3.18.2")
    ],
    targets: [
        .target(
            name: "SharedConnectionService",
            dependencies: []),
        .target(
            name: "ReactiveSharedConnectionService",
            dependencies: [
                .target(name: "SharedConnectionService"),
                "ReactiveKit"
            ],
            path: "Sources/ReactiveKit"),
        .testTarget(
            name: "SharedConnectionServiceTests",
            dependencies: ["SharedConnectionService"])
    ]
)
