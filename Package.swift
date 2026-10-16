// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QueueCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "QueueCore", targets: ["QueueCore"])
    ],
    targets: [
        .target(
            name: "QueueCore",
            path: "Sources/QueueCore"
        ),
        .testTarget(
            name: "QueueCoreTests",
            dependencies: ["QueueCore"],
            path: "Tests/QueueCoreTests"
        )
    ]
)
