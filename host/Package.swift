// swift-tools-version: 6.0
import PackageDescription

// `make lean` builds the Lean libraries, merges them with Lean's runtime into
// ../build/lib/libcairn_lean.a and vendors lean.h into Sources/CLean/vendor.
let leanLib = Context.packageDirectory + "/../build/lib"

let package = Package(
    name: "CairnHost",
    platforms: [.macOS("27.0")],
    targets: [
        // The C shim over lean.h, and the link line for the Lean library.
        .target(
            name: "CLean",
            cSettings: [.headerSearchPath("vendor"), .unsafeFlags(["-Wno-shorten-64-to-32"])],
            linkerSettings: [.unsafeFlags(["-L" + leanLib, "-lcairn_lean", "-lc++"])]
        ),
        // The frame and event model (and, from workstream E, their byte codecs).
        .target(name: "CairnFrame"),
        .target(name: "CairnRender", dependencies: ["CairnFrame"]),
        .testTarget(name: "CairnRenderTests", dependencies: ["CairnRender", "CairnFrame"], exclude: ["Goldens"]),
        // Lean's TextMetrics.host against the renderer, through the real extern and C glue.
        .target(name: "CairnLeanText", dependencies: ["CLean"], path: "Tests/CairnLeanText"),
        .testTarget(name: "CairnRenderLeanTests", dependencies: ["CairnRender", "CairnLeanText"]),

        // The generic AppKit host: threads, input, text input, accessibility, effects.
        .target(name: "CairnHost", dependencies: ["CLean", "CairnFrame"]),

        // Apps: one executable per Lean app.
        .executableTarget(name: "CairnCounter", dependencies: ["CairnHost", "CLean", "CairnFrame"]),
        // A Swift stand-in app with a text field, for checking the host by hand (IME, AX) before
        // a Lean app has one. Not product code.
        .executableTarget(name: "CairnFixture", dependencies: ["CairnHost", "CairnFrame"]),

        .testTarget(name: "CairnHostTests", dependencies: ["CairnHost", "CairnFrame"]),
    ]
)
