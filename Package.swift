// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPController",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MCPController", targets: ["MCPController"])
    ],
    targets: [
        .executableTarget(
            name: "MCPController",
            path: "Sources/MCPController"
        ),
        .testTarget(
            name: "MCPControllerTests",
            dependencies: ["MCPController"],
            path: "Tests/MCPControllerTests"
        )
    ]
)
