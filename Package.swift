// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MacMiddle",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MacMiddleCore", path: "Sources", exclude: ["main.swift"]),
        .testTarget(name: "MacMiddleCoreTests", dependencies: ["MacMiddleCore"], path: "Tests")
    ]
)
