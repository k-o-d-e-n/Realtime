// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Realtime+FoundationDB",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "Realtime+FoundationDB",
            targets: ["Realtime+FoundationDB"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/FoundationDB/fdb-swift-bindings.git", ._branchItem("master")),
        .package(url: "../..", .branch("master"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "Realtime+FoundationDB",
            dependencies: ["Realtime", "FoundationDB"]),
        .testTarget(
            name: "Realtime+FoundationDBTests",
            dependencies: ["Realtime+FoundationDB"]),
    ]
)
