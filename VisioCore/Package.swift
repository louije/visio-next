// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VisioCore", targets: ["VisioCore"]),
    ],
    targets: [
        .target(name: "VisioCore"),
        .testTarget(name: "VisioCoreTests", dependencies: ["VisioCore"]),
    ]
)
