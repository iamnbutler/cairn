// swift-tools-version: 6.0
// The `cairn` command (docs/cli.md): new, add, build, doc, publish, and login. It
// wraps lake, bin/cairn-link and swift; it has no dependencies, so it builds offline.
import PackageDescription

let package = Package(
    name: "cairn-tool",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "cairn", targets: ["cairn"])],
    targets: [
        .target(name: "CairnTool"),
        .executableTarget(name: "cairn", dependencies: ["CairnTool"]),
        .testTarget(name: "CairnToolTests", dependencies: ["CairnTool"]),
    ]
)
