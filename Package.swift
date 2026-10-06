// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LlamaBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LlamaBar", targets: ["LlamaBar"])],
    targets: [
        .target(name: "CProcessSupport"),
        .target(name: "LlamaBarCore", dependencies: ["CProcessSupport"]),
        .executableTarget(name: "LlamaBar", dependencies: ["LlamaBarCore"]),
        .testTarget(
            name: "LlamaBarCoreTests", dependencies: ["LlamaBarCore"],
            resources: [.copy("Fixtures")]),
    ]
)
