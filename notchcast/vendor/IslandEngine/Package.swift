// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IslandEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "IslandCore", targets: ["IslandCore"]),
        .library(name: "IslandUI", targets: ["IslandUI"]),
    ],
    targets: [
        .target(name: "IslandCore", dependencies: []),
        .target(name: "IslandUI", dependencies: ["IslandCore"]),
    ],
    swiftLanguageModes: [.v6]
)
