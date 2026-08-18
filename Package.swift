// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeroSip",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MeroSipLib",
            targets: ["MeroSipLib"]
        ),
        .executable(
            name: "MeroSipApp",
            targets: ["MeroSipApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MeroSipLib",
            path: "Sources/MeroSipLib"
        ),
        .executableTarget(
            name: "MeroSipApp",
            dependencies: ["MeroSipLib"],
            path: "Sources/MeroSipApp"
        ),
        .testTarget(
            name: "MeroSipTests",
            dependencies: ["MeroSipLib"],
            path: "Tests/MeroSipTests"
        )
    ]
)
