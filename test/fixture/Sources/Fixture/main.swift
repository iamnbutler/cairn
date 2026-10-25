import AppKit
import CFixture
import CLean
import CairnFrame
import CairnHost
import CairnRender
import Metal
import QuartzCore

// Cairn's fixture app (lean/Fixture.lean) on Cairn's host, as an app in its own repository has
// it. `make check` runs `--selftest`, `cairn bench` runs `--bench`, `cairn conformance` runs it
// with its debug socket on.
//   Fixture               open the window
//   Fixture --selftest    drive the host headlessly through its real threads and check it
//   Fixture --bench       input → frame and frame size with 10 and 1,000 items

let fixture = LeanApp(
    module: runtime_initialize_fixture_Fixture_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

let size = Size(w: 480, h: 600)
let args = CommandLine.arguments

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("selftest: FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func center(_ r: Rect) -> Point { Point(x: r.x + r.w / 2, y: r.y + r.h / 2) }

func click(_ p: Point) -> [Event] {
    [.pointerMove(p), .pointerDown(p, .primary, clicks: 1, Mods()), .pointerUp(p, .primary, Mods())]
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

/// The headless check: the real engine (Lean thread, v1 codec, timers), the real view (text
/// input client, accessibility mirror), no window. It types and presses through the entry points
/// AppKit and assistive apps use, waits for a timer the app set, and checks the frame, the AX
/// tree and a painted pixel.
@MainActor
enum SelfTest {
    static func run() {
        let engine = Engine(size: size, scalePercent: 200) { LeanCore(fixture) }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }

        @discardableResult
        func settle(_ seq: UInt64 = engine.lastSeq) -> Frame {
            guard let p = engine.wait(through: seq) else { fail("no frame through #\(seq)") }
            view.applyLatestFrame()
            return p.frame
        }
        func elements() -> [NSAccessibilityElement] {
            var out: [NSAccessibilityElement] = []
            func walk(_ xs: [Any]?) {
                for case let e as NSAccessibilityElement in xs ?? [] { out.append(e); walk(e.accessibilityChildren()) }
            }
            walk(view.accessibilityChildren())
            return out
        }
        func need(_ id: String) -> NSAccessibilityElement {
            guard let e = elements().first(where: { $0.accessibilityIdentifier() == id }) else {
                fail("\(id) not in the accessibility tree")
            }
            return e
        }
        func ids(_ prefix: String) -> [String] {
            elements().compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix(prefix) }
        }
        func label(_ suffix: String) -> String? {
            elements().compactMap { e -> String? in
                guard e.accessibilityRole() == .staticText, let l = e.accessibilityLabel(), l.hasSuffix(suffix) else { return nil }
                return l
            }.first
        }
        func press(_ id: String) {
            if !need(id).accessibilityPerformPress() { fail("AXPress on \(id) refused") }
            settle()
        }
        func type(_ s: String) {
            view.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
            settle()
        }
        func expect(_ what: String, _ got: some Equatable, _ want: some Equatable) {
            if String(describing: got) != String(describing: want) { fail("\(what): \(got), expected \(want)") }
        }

        var f = settle()
        expect("first frame size", "\(f.size.w)x\(f.size.h)", "480x600")
        if need("^2").accessibilityRole() != .textField { fail("^2 is not a text field") }
        if need("^3").accessibilityRole() != .button { fail("^3 is not a button") }
        expect("left at start", label(" left") ?? "", "0 items left")

        // Focus the field (an AX focus is a click at its centre), type, press Enter.
        need("^2").setAccessibilityFocused(true)
        f = settle()
        if f.textInput?.control.label != "^2" { fail("the field is not focused after an AX focus") }
        type("  Buy milk ")
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        settle()
        expect("checkboxes after Enter", ids("^4"), ["^4#1"])
        expect("item label (trimmed)", need("^4#1").accessibilityLabel() ?? "", "Buy milk")

        // Type again, then press Add; toggle item 1; delete item 2.
        type("Eggs")
        press("^3")
        expect("checkboxes after Add", ids("^4"), ["^4#1", "^4#2"])
        press("^4#1")
        expect("^4#1 value", need("^4#1").accessibilityValue() as? Int ?? -1, 1)
        expect("left after toggle", label(" left") ?? "", "1 item left")
        press("^5#2")
        expect("delete buttons after delete", ids("^5"), ["^5#1"])

        // Flash: its timer comes back through the host's clock, and the note goes.
        press("^6")
        if label("Flashing") == nil { fail("no Flashing note after a press on ^6") }
        let deadline = hostNow() + 5
        while label("Flashing") != nil {
            if hostNow() > deadline { fail("the Flash timer never fired") }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            view.applyLatestFrame()
        }

        // Tab moves keyboard focus in paint order: field, then Add.
        f = settle(engine.send([.pointerExit, .key(.tab, Mods())]))
        expect("focus after Tab", f.ax.first { $0.focused }?.control?.label ?? "none", "^2")
        if view.shadowDivergences.count != 0 { fail("text shadow diverged: \(view.shadowDivergences)") }

        // The frame paints what it says: Add's fill, clear of its label.
        f = settle(engine.send([.key(.escape, Mods())]))
        guard let add = f.ax.first(where: { $0.control?.label == "^3" }) else { fail("^3 not in frame") }
        do {
            let c = try Renderer().probe(f, at: Point(x: add.rect.x + 3, y: add.rect.y + add.rect.h / 2))
            expect("Add fill", "\(c.r),\(c.g),\(c.b)", "0,122,255")
        } catch { fail("render: \(error)") }

        engine.stop()
        print("selftest: PASS (Fixture: focus, type, Enter, Add, toggle, delete, timer, Tab, AX, paint)")
    }
}

/// Lean through the real exports and codec, with no threads: input → frame (encode events, step,
/// frame, decode) and the frame's size in bytes.
enum Bench {
    static func run() {
        LeanRuntime.enter(module: fixture.module)
        let codec = FrameV1Codec()
        print("Fixture bench (release, LEAN_ABORT_ON_NONLINEAR=\(ProcessInfo.processInfo.environment["LEAN_ABORT_ON_NONLINEAR"] ?? "unset"))")
        for n in [10, 1000] {
            var state = cairn_app_init(UInt32(size.w), UInt32(size.h), 200)!
            func step(_ es: [Event]) { state = cairn_app_step(state, LeanRuntime.bytes(codec.encode(es)))! }
            func frame() -> (Frame, Int) {
                cairn_lean_inc(state)
                return try! LeanRuntime.withBytes(cairn_app_frame(state)!) { (try codec.decodeFrame($0), $0.count) }
            }
            func ax(_ id: String) -> Rect {
                guard let r = frame().0.ax.first(where: { $0.control?.label == id })?.rect else { fail("\(id) not in frame") }
                return r
            }
            step(click(center(ax("^2"))))
            var adds: [Event] = []
            for i in 0..<n { adds += [.insertText("Item \(i + 1)"), .key(.enter, Mods())] }
            let t0 = hostNow()
            step(adds)
            let addMs = (hostNow() - t0) * 1000
            let (f, bytes) = frame()
            precondition(f.ax.filter { $0.control?.claim == 4 }.count == n)
            let toggle = center(ax("^4#1"))

            func time(_ label: String, _ events: () -> [Event]) {
                var ms: [Double] = []
                for i in 0..<60 {
                    let es = events()
                    let t0 = hostNow()
                    step(es)
                    _ = frame()
                    if i >= 10 { ms.append((hostNow() - t0) * 1000) }
                }
                ms.sort()
                print(String(format: "    %@: p50 %.3f ms, p95 %.3f ms", label, ms[ms.count / 2], ms[ms.count * 95 / 100]))
            }
            print("  \(n) items: frame \(bytes) bytes, \(f.draws.count) draws, \(f.ax.count) ax nodes; adding them took \(String(format: "%.1f", addMs)) ms")
            time("type one character (field focused)") { [.insertText("x")] }
            time("click a checkbox (move, down, up)") { click(toggle) }
            var x: Int32 = 0
            time("pointer move (hover)") { x = (x + 7) % 400; return [.pointerMove(Point(x: 20 + x, y: 300))] }
            cairn_lean_dec(state)
        }
    }
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

if args.contains("--bench") {
    Bench.run()
    exit(0)
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Fixture", size: size) { LeanCore(fixture) })
}
