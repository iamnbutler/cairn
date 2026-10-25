// swift-tools-version: 6.0
// The fixture's host: Cairn's AppKit host, linking .cairn/lib/libfixture.a, which `cairn build`
// makes from the Lean code (bin/cairn-link). It depends on the checkout it is in, by path.
import Foundation
import PackageDescription

let lib = Context.packageDirectory + "/.cairn/lib"
// SwiftPM names a path dependency after its directory: `cairn` in a clone, the lane's name in a
// lane (AGENTS.md, "Workflow: lane").
let cairnDir = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
let cairn = cairnDir.lastPathComponent.lowercased()

let package = Package(
    name: "fixture",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: cairnDir.path)],
    targets: [
        // The Lean export Cairn's CLean doesn't declare: the app's initializer.
        .target(name: "CFixture", dependencies: [.product(name: "CLean", package: cairn)]),
        .executableTarget(
            name: "Fixture",
            dependencies: ["CFixture",
                           .product(name: "CLean", package: cairn),
                           .product(name: "CairnFrame", package: cairn),
                           .product(name: "CairnRender", package: cairn),
                           .product(name: "CairnHost", package: cairn)],
            linkerSettings: [.unsafeFlags(["-L" + lib, "-lfixture"])]),
    ]
)
