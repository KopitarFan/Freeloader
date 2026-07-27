// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Freeloader",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Freeloader", targets: ["NuFinder"])],
    targets: [
        .executableTarget(
            name: "NuFinder",
            path: "Sources/NuFinder"
        ),
        .testTarget(
            name: "NuFinderTests",
            dependencies: ["NuFinder"],
            path: "Tests/NuFinderTests"
        )
    ]
)
