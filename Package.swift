// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LlamaMenuBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LlamaMenuBar", targets: ["LlamaMenuBar"])],
    targets: [
        .target(name: "CProcessSupport"),
        .target(name: "LlamaMenuCore", dependencies: ["CProcessSupport"]),
        .executableTarget(name: "LlamaMenuBar", dependencies: ["LlamaMenuCore"]),
        .testTarget(
            name: "LlamaMenuCoreTests", dependencies: ["LlamaMenuCore"],
            resources: [.copy("Fixtures")]),
    ]
)
