// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CreaseEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CreaseEngine", targets: ["CreaseEngine"])],
    targets: [
        .target(name: "CreaseEngine"),
        .testTarget(name: "CreaseEngineTests", dependencies: ["CreaseEngine"], resources: [.copy("Fixtures")]),
    ]
)
