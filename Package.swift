// swift-tools-version:5.2

import PackageDescription

var packageDependencies: [Package.Dependency] = [
    .package(name: "Promise.swift", url: "https://github.com/k-o-d-e-n/promise.swift.git", .branch("master"))
]
var targetDependencies: [Target.Dependency] = [
    .product(name: "Promise.swift", package: "Promise.swift")
]
#if os(Linux)
packageDependencies += [
    .package(url: "https://github.com/apple/swift-se-0282-experimental", .branch("master"))
]
targetDependencies += [
    .product(name: "SE0282_Experimental", package: "swift-se-0282-experimental"),
]
#endif

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
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "Realtime",
            dependencies: targetDependencies
        ),
        .target(
            name: "Realtime+Firebase",
            dependencies: ["Realtime"]
        ),
        .target(
            name: "RealtimeTestLib",
            dependencies: ["Realtime"],
            path: "./Tests/RealtimeTestLib"
        ),
        .testTarget(
            name: "RealtimeTests",
            dependencies: ["RealtimeTestLib"]
        ),
    ]
)
