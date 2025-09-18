// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftGTDModules",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "Services", targets: ["Services"]),
        .library(name: "Features", targets: ["Features"])
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Models", dependencies: ["Core"]),
        .target(name: "Networking", dependencies: ["Models"]),
        .target(name: "Services", dependencies: ["Models", "Networking"]),
        .target(name: "Features", dependencies: ["Core", "Models", "Services"]),
        // Test targets
        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking", "Models", "Core"]
        ),
        .testTarget(
            name: "ServicesTests",
            dependencies: ["Services", "Networking", "Models", "Core"]
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Features", "Services", "Networking", "Models", "Core"]
        )
    ]
)
