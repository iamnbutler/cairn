// swift-tools-version: 6.0
import PackageDescription

// `make lean` builds the Lean libraries, merges them with Lean's runtime into
// ../build/lib/libcairn_lean.a and vendors lean.h into Sources/CLean/vendor.
let leanLib = Context.packageDirectory + "/../build/lib"

let package = Package(
    name: "CairnHost",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CLean",
            cSettings: [.headerSearchPath("vendor")],
            linkerSettings: [.unsafeFlags(["-L" + leanLib, "-lcairn_lean", "-lc++"])]
        ),
        .executableTarget(
            name: "CairnSpike",
            dependencies: ["CLean"]
        ),
    ]
)
