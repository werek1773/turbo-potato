// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoulderKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "BoulderKit", targets: ["BoulderKit"]),
    ],
    targets: [
        .target(name: "BoulderKit"),
        .testTarget(name: "BoulderKitTests", dependencies: ["BoulderKit"]),
    ]
)
