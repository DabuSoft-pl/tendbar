// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TendbarKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TendbarKit", targets: ["TendbarKit"]),
    ],
    targets: [
        .target(name: "TendbarKit"),
        .testTarget(name: "TendbarKitTests", dependencies: ["TendbarKit"]),
    ]
)
