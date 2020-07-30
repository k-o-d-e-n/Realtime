// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Realtime",
    products: [
        .library(
            name: "Realtime",
            targets: ["Realtime"]
        ),
        .library(
            name: "RealtimeTestLib",
            targets: ["RealtimeTestLib"]
        ),
        .library(
            name: "Realtime+Firebase",
            targets: ["Realtime+Firebase"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-se-0282-experimental.git", .branch("master")),
        .package(name: "Promise.swift", url: "https://github.com/k-o-d-e-n/promise.swift.git", .branch("master"))
    ],
    targets: [
        .target(
            name: "Realtime",
            dependencies: [
                .product(name: "SE0282_Experimental", package: "swift-se-0282-experimental"),
                .product(name: "Promise.swift", package: "Promise.swift")
            ]
        ),
        .target(
            name: "Realtime+Firebase",
            dependencies: ["Realtime"]
        ),
        .target(
            name: "RealtimeTestLib",
            dependencies: ["Realtime"],
            path: "./Tests/RealtimeTestLib",
            sources: ["./", "../../Example/Realtime/Entities.swift"]
        ),
        .testTarget(
            name: "RealtimeTests",
            dependencies: ["RealtimeTestLib"]
        ),
    ]
)
