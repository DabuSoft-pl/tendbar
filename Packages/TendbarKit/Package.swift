// swift-tools-version: 6.0
import PackageDescription

// Clean Architecture: dependencies point inwards only.
// Domain <- Application <- Infrastructure. The compiler enforces it: Domain cannot import anything of ours,
// Application sees only Domain, and only Infrastructure (and the app's composition root) touches files and sockets.
let package = Package(
    name: "TendbarKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TendbarDomain", targets: ["TendbarDomain"]),
        .library(name: "TendbarApplication", targets: ["TendbarApplication"]),
        .library(name: "TendbarInfrastructure", targets: ["TendbarInfrastructure"]),
    ],
    targets: [
        .target(name: "TendbarDomain"),
        .target(name: "TendbarApplication", dependencies: ["TendbarDomain"]),
        .target(name: "TendbarInfrastructure", dependencies: ["TendbarDomain", "TendbarApplication"]),
        .testTarget(name: "TendbarDomainTests", dependencies: ["TendbarDomain"]),
        .testTarget(name: "TendbarApplicationTests", dependencies: ["TendbarDomain", "TendbarApplication"]),
        .testTarget(name: "TendbarInfrastructureTests", dependencies: ["TendbarDomain", "TendbarApplication", "TendbarInfrastructure"]),
    ]
)
