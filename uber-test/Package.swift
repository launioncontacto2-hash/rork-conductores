// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UberTest",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "UberTestCore", targets: ["UberTestCore"])],
    targets: [
        .target(name: "UberTestCore"),
        .testTarget(name: "UberTestCoreTests", dependencies: ["UberTestCore"])
    ]
)
