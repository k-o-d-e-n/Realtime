// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Realtime",
//    platforms: [
//        .iOS(.v9), .macOS(.v10_10)
//    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
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
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/glessard/swift-atomics.git", from: "5.0.1"),
        .package(url: "https://github.com/k-o-d-e-n/promise.swift.git", ._branchItem("master"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "Realtime",
            dependencies: ["CAtomics", "Promise.swift"]
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
