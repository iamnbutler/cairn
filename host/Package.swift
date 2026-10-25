// swift-tools-version: 6.0
import PackageDescription

// The development package: the host's tests and fuzzers. Apps depend on the root package
// (../Package.swift) at a tag instead; its library targets are these sources again, without the
// development link line below.
//
// `make lean` builds the Lean libraries, merges the framework with Lean's runtime into
// ../build/lib/libcairn_lean.a (linked through CLean) and vendors lean.h into Sources/CLean/vendor.
let leanLib = Context.packageDirectory + "/../build/lib"

let package = Package(
    name: "CairnHost",
    platforms: [.macOS("27.0")],
    products: [
        // Core Text metrics as a static library, for Lean executables that must lay out exactly
        // as the running app does (the conformance generator, tools/conformance).
        .library(name: "CairnMetrics", type: .static, targets: ["CairnRender"]),
    ],
    targets: [
        // The C shim over lean.h, and the link line for the Lean library.
        .target(
            name: "CLean",
            cSettings: [.headerSearchPath("vendor"), .unsafeFlags(["-Wno-shorten-64-to-32"])],
            linkerSettings: [.unsafeFlags(["-L" + leanLib, "-lcairn_lean", "-lc++"])]
        ),
        // The frame and event model (and, from workstream E, their byte codecs).
        .target(name: "CairnFrame"),
        // Decoder and event encoder against the corpus Lean writes (`make corpus`).
        .testTarget(name: "CairnFrameTests", dependencies: ["CairnFrame"]),
        .target(name: "CairnRender", dependencies: ["CairnFrame"]),
        .testTarget(name: "CairnRenderTests", dependencies: ["CairnRender", "CairnFrame"], exclude: ["Goldens"]),
        // Lean's TextMetrics.host against the renderer, through the real extern and C glue.
        .target(name: "CairnLeanText", dependencies: ["CLean"], path: "Tests/CairnLeanText"),
        .testTarget(name: "CairnRenderLeanTests", dependencies: ["CairnRender", "CairnLeanText"]),

        // The generic AppKit host: threads, input, text input, accessibility, effects.
        .target(name: "CairnHost", dependencies: ["CLean", "CairnFrame", "CairnRender"]),

        // Headless screenshots with pins (`--map-capture`, `--try-capture`): each app's executable
        // calls MapCapture.main, since each links its own app.
        .target(name: "CairnCapture", dependencies: ["CairnHost", "CairnFrame", "CairnRender"]),

        // A Swift stand-in app with a text field, for checking the host by hand (IME, AX) before
        // a Lean app has one. Not product code.
        .executableTarget(name: "CairnFixture", dependencies: ["CairnHost", "CairnFrame", "CairnRender"]),

        .testTarget(name: "CairnHostTests", dependencies: ["CairnHost", "CairnFrame"]),

        // The trusted-base fuzzer (docs/fuzz.md, "Trusted base"): the Swift side of each trusted
        // boundary against Lean's proved side, in one process. Not product code; `make
        // fuzz-trusted` runs it. Dump.swift is a symlink to CairnFrameTests' canonical dump.
        .target(name: "CairnTrustedLean", dependencies: ["CLean"], path: "Tests/CairnTrustedLean"),
        .executableTarget(name: "CairnFuzzTrusted",
                          dependencies: ["CairnHost", "CairnFrame", "CairnRender", "CLean", "CairnTrustedLean"],
                          path: "Tests/CairnFuzzTrusted",
                          swiftSettings: [.swiftLanguageMode(.v5)],
                          linkerSettings: [.unsafeFlags(["-L" + leanLib, "-lcairn_trusted_fuzz"])]),
    ]
)
