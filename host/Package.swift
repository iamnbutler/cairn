// swift-tools-version: 6.0
import PackageDescription

// `make lean` builds the Lean libraries, merges them with Lean's runtime into
// ../build/lib/libcairn_lean.a and vendors lean.h into Sources/CLean/vendor.
let leanLib = Context.packageDirectory + "/../build/lib"

let package = Package(
    name: "CairnHost",
    platforms: [.macOS("27.0")],
    targets: [
        .target(
            name: "CLean",
            cSettings: [.headerSearchPath("vendor"), .unsafeFlags(["-Wno-shorten-64-to-32"])],
            linkerSettings: [.unsafeFlags(["-L" + leanLib, "-lcairn_lean", "-lc++"])]
        ),
        .target(name: "CairnFrame"),
        .target(name: "CairnRender", dependencies: ["CairnFrame"]),
        .testTarget(name: "CairnRenderTests", dependencies: ["CairnRender", "CairnFrame"], exclude: ["Goldens"]),
        // Lean's TextMetrics.host against the renderer, through the real extern and C glue.
        .target(name: "CairnLeanText", dependencies: ["CLean"], path: "Tests/CairnLeanText"),
        .testTarget(name: "CairnRenderLeanTests", dependencies: ["CairnRender", "CairnLeanText"]),
        .executableTarget(
            name: "CairnSpike",
            dependencies: ["CLean"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
