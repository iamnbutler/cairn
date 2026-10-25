/// What `cairn new` writes besides cairn.toml. An app (`bin`) is a working one: a window with a
/// count and a Count button (a place and a move, `<name>^1` and `^2`), its v1 exports, the C
/// declaration of its initializer, and a host with a `--selftest`. `make new-check` (Cairn's
/// Makefile, tools/cairn/new-check.sh) builds and runs one against the checkout it is in.
enum Template {
    /// The macOS version Cairn's host products need (the root Package.swift's `platforms`).
    static let macOS = "27.0"

    /// Lean's spelling of a package name in symbol names: `_` is doubled (`Name.mangle`).
    static func mangled(_ name: String) -> String { name.replacing("_", with: "__") }

    static func files(name: String, module: String, kind: Kind, toolchain: String) -> [(String, String)] {
        let lib = kind == .lib
        var files: [(String, String)] = [
            ("claims.lock", "# id\tkind\tstatus\tstatement\ttitle\n"),
            (".gitignore", ".lake/\n.build/\n.cairn/\nbuild/\n"),
            ("lean/lean-toolchain", toolchain),
            ("lean/lakefile.lean", """
                import Lake
                open Lake DSL

                package \(name) where
                  leanOptions := #[⟨`weak.cairn.claims.scope, "\(name)"⟩]

                require "owner" / "cairn" @ "^0.1.0"

                @[default_target]
                lean_lib \(module) where
                \(lib ? "" : "  roots := #[`\(module).Abi, `\(module)]\n")  defaultFacets := #[LeanLib.staticFacet]

                """),
        ]
        guard !lib else {
            files.append(("lean/\(module).lean", """
                module

                public import Cairn

                /-! \(module): a Cairn library. Its claims are `\(name)^N`. -/

                @[expose] public section

                namespace \(module)

                end \(module)

                """))
            return files
        }
        let initializer = "runtime_initialize_\(mangled(name))_\(module)_Abi"
        files += [
            ("lean/\(module).lean", """
                module

                public import Cairn

                /-! \(module): a Cairn app. Its claims are `\(name)^N`, locked in claims.lock (Cairn's
                docs/claims.md); its exports are in `\(module).Abi`. -/

                @[expose] public section

                namespace \(module)
                open Cairn Cairn.Claims

                structure State where
                  count : Nat := 0
                deriving Repr, DecidableEq, Inhabited

                place ^1 window "\(module) window" where
                  does "The app's window: the count and a Count button."

                move ^2 count (s : State) "Count" in ^1 where
                  does "Press Count."
                  sees "The count goes up by one."
                  on press
                    apply := { s with count := s.count + 1 }
                    post s' := s'.count = s.count + 1
                    sound := by intro s; rfl

                def machine : Machine State := { init := {}, moves := moves% }

                def claimInfos : List ClaimInfo := claims%

                def white : Color := ⟨255, 255, 255, 255⟩
                def ink : Color := ⟨28, 28, 30, 255⟩
                def green : Color := ⟨48, 160, 80, 255⟩

                def view (s : State) (_ : UI) : Node :=
                  .box { width := .fill, height := .fill, padding := ⟨40, 40, 40, 40⟩, gap := 16,
                         background := some white, clip := true } none
                    [ .box { width := .fill, height := .fixed 20, clip := true } none
                        [.text { font := { size := 15 }, color := ink } s!"Count: {s.count}"],
                      .box { width := .fixed 160, height := .fixed 44, radius := 6, align := .center,
                             justify := .center, clip := true, background := some green }
                        (some { ref := ⟨2, 0⟩, label := "Count" })
                        [.text { font := { size := 15, weight := 600 }, color := white } "Count"] ]

                def app : App State := machine.toApp [.window 1 "\(module)" view] claimInfos

                end \(module)

                """),
            ("lean/\(module)/Abi.lean", """
                module

                public import \(module)

                /-! \(module)'s v1 exports (Cairn's docs/runtime.md), which the host calls. The host starts
                the app with `\(initializer)`. -/

                @[expose] public section

                namespace \(module)
                open Cairn

                /-- Core Text metrics in the running app. -/
                def cfg : Runtime.Config := { metrics := TextMetrics.host }

                @[export cairn_app_init]
                def appInit (w h scalePercent : UInt32) : Runtime.State State :=
                  Runtime.initState app cfg w h scalePercent

                @[export cairn_app_step]
                def appStep (s : Runtime.State State) (events : ByteArray) : Runtime.State State :=
                  Runtime.stepBytes app cfg Frame.boundary s events

                @[export cairn_app_frame]
                def appFrame (s : Runtime.State State) : ByteArray := Runtime.frameBytes Frame.boundary s

                end \(module)

                """),
            ("Package.swift", """
                // swift-tools-version: 6.0
                // The app's host: Cairn's AppKit host, linking .cairn/lib/lib\(name).a, which
                // `cairn build` makes from the Lean code (bin/cairn-link).
                import PackageDescription

                let lib = Context.packageDirectory + "/.cairn/lib"

                let package = Package(
                    name: "\(name)",
                    platforms: [.macOS("\(macOS)")],
                    dependencies: [.package(url: "CAIRN_GIT_URL", from: "0.1.0")],
                    targets: [
                        // The Lean exports Cairn's CLean doesn't declare: the app's initializer.
                        .target(name: "C\(module)", dependencies: [.product(name: "CLean", package: "cairn")]),
                        .executableTarget(
                            name: "\(module)",
                            dependencies: ["C\(module)",
                                           .product(name: "CLean", package: "cairn"),
                                           .product(name: "CairnFrame", package: "cairn"),
                                           .product(name: "CairnHost", package: "cairn")],
                            linkerSettings: [.unsafeFlags(["-L" + lib, "-l\(name)"])]),
                    ]
                )

                """),
            ("Sources/C\(module)/include/\(name).h", """
                // \(module)'s Lean exports, from lean/\(module)/Abi.lean. Cairn's CLean declares the
                // runtime and the v1 app ABI (`cairn_app_init`, `cairn_app_step`, `cairn_app_frame`).
                #pragma once
                #include <stdint.h>
                #include "cairn_lean.h"

                // The app module's initializer, named after the package and the module.
                cairn_obj *\(initializer)(uint8_t builtin);

                """),
            ("Sources/C\(module)/\(name).c", "#include \"\(name).h\"\n"),
            ("Sources/\(module)/main.swift", """
                import C\(module)
                import CairnFrame
                import CairnHost
                import Foundation

                // \(module) on Cairn's host (Cairn's docs/package.md).
                //   \(module)               open the window
                //   \(module) --selftest    run the Lean side headlessly: press Count, check the count

                let app = LeanApp(
                    module: \(initializer),
                    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
                    step: { cairn_app_step($0, $1) },
                    frame: { cairn_app_frame($0) },
                    codec: FrameV1Codec())

                let size = Size(w: 480, h: 320)

                if CommandLine.arguments.contains("--selftest") {
                    func fail(_ message: String) -> Never {
                        FileHandle.standardError.write(Data("selftest: FAIL: \\(message)\\n".utf8))
                        exit(1)
                    }
                    let engine = Engine(size: size, scalePercent: 200) { LeanCore(app) }
                    engine.start()
                    guard let first = engine.wait(through: 0) else { fail("no first frame") }
                    guard let button = first.frame.ax.first(where: { $0.control?.label == "^2" }) else { fail("no Count button (^2)") }
                    let c = Point(x: button.rect.x + button.rect.w / 2, y: button.rect.y + button.rect.h / 2)
                    let seq = engine.send([.pointerMove(c), .pointerDown(c, .primary, clicks: 1, Mods()), .pointerUp(c, .primary, Mods())])
                    guard let after = engine.wait(through: seq) else { fail("no frame after the click") }
                    guard after.frame.ax.contains(where: { $0.label == "Count: 1" }) else { fail("the count isn't 1 after a press on ^2") }
                    engine.stop()
                    print("selftest: PASS (\(module): first frame, a press on ^2)")
                    exit(0)
                }

                MainActor.assumeIsolated {
                    CairnApp.main(CairnApp.Config(title: "\(module)", size: size) { LeanCore(app) })
                }

                """),
        ]
        return files
    }
}
