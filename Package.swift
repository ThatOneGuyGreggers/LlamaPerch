// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LlamaPerch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LlamaPerch", targets: ["LlamaPerch"])],
    targets: [
        .target(name: "CProcessSupport"),
        .target(name: "LlamaPerchCore", dependencies: ["CProcessSupport"]),
        .executableTarget(name: "LlamaPerch", dependencies: ["LlamaPerchCore"]),
        .testTarget(
            name: "LlamaPerchCoreTests", dependencies: ["LlamaPerchCore"],
            resources: [.copy("Fixtures")]),
    ]
)
