// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UberTest",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "UberTestCore", targets: ["UberTestCore"])],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(name: "UberTestCore", dependencies: [
            .product(name: "Supabase", package: "supabase-swift")
        ]),
        .testTarget(name: "UberTestCoreTests", dependencies: ["UberTestCore"])
    ]
)
