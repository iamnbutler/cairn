// swift-tools-version: 6.0
import PackageDescription

// Cairn's Swift side as a package other apps depend on, at a tag:
//
//     .package(url: "https://github.com/iamnbutler/cairn", from: "0.1.0")
//
// Library products only, and no `unsafeFlags` (SwiftPM refuses them in a versioned dependency).
// Nothing here links Lean: the app links one static library that `bin/cairn-link` merges from
// Lean's runtime, Cairn's Lean library and the app's own (docs/package.md), from its own root
// manifest, where `unsafeFlags` are allowed. Lean's header ships in CLean/vendor.
//
// The sources are host/'s. host/Package.swift is the development package (the host's tests and
// fuzzers, linked against ../build/lib); it declares these targets again with the
// development link line. Keep the two in step.
let package = Package(
    name: "Cairn",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "CLean", targets: ["CLean"]),
        .library(name: "CairnFrame", targets: ["CairnFrame"]),
        .library(name: "CairnRender", targets: ["CairnRender"]),
        .library(name: "CairnHost", targets: ["CairnHost"]),
        .library(name: "CairnCapture", targets: ["CairnCapture"]),
    ],
    targets: [
        // The C shim over lean.h. The Lean symbols it calls come from the app's merged library.
        .target(name: "CLean", path: "host/Sources/CLean",
                cSettings: [.headerSearchPath("vendor")],
                linkerSettings: [.linkedLibrary("c++")]),
        .target(name: "CairnFrame", path: "host/Sources/CairnFrame"),
        .target(name: "CairnRender", dependencies: ["CairnFrame"], path: "host/Sources/CairnRender"),
        .target(name: "CairnHost", dependencies: ["CLean", "CairnFrame", "CairnRender"],
                path: "host/Sources/CairnHost"),
        .target(name: "CairnCapture", dependencies: ["CairnHost", "CairnFrame", "CairnRender"],
                path: "host/Sources/CairnCapture"),
    ]
)
