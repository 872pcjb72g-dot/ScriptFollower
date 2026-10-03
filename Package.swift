// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScriptFollower",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ScriptFollower", targets: ["ScriptFollower"]),
    ],
    targets: [
        .target(name: "ScriptFollower"),
        .testTarget(name: "ScriptFollowerTests", dependencies: ["ScriptFollower"]),
    ]
)
