import AppKit
import CLean
import CairnCapture
import CairnFrame
import CairnHost
import CairnRender
import Metal
import QuartzCore

// Basics (lean/Examples/Basics.lean): the first app on the v1 ABI.
//   CairnBasics               open the window (add --stats for latency, --latency N to measure)
//   CairnBasics --selftest    drive the host headlessly through its real threads and check it
//   CairnBasics --bench       input → frame and frame size with 10 and 1,000 items

let basics = LeanApp(
    module: runtime_initialize_cairn_Examples_Basics,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

let size = Size(w: 480, h: 600)
let args = CommandLine.arguments

// `--map-capture <script.json> <out dir>`: headless screenshots with pins (`make capture`, docs/claim-pages.md).
if let code = MapCapture.main(args, size: size, core: { LeanCore(basics) }) { exit(code) }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func center(_ r: Rect) -> Point { Point(x: r.x + r.w / 2, y: r.y + r.h / 2) }

func click(_ p: Point) -> [Event] {
    [.pointerMove(p), .pointerDown(p, .primary, clicks: 1, Mods()), .pointerUp(p, .primary, Mods())]
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

if args.contains("--bench") {
    Bench.run()
    exit(0)
}

/// The headless check `make check` runs: the real engine (Lean thread, v1 codec), the real view
/// (text input client, accessibility mirror), no window. It clicks, types and presses through
/// the same entry points AppKit and assistive apps use, then checks the frame and the AX tree.
@MainActor
enum SelfTest {
    static func run() {
        let engine = Engine(size: size, scalePercent: 200) { LeanCore(basics) }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }

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
        func element(_ id: String) -> NSAccessibilityElement? {
            elements().first { $0.accessibilityIdentifier() == id }
        }
        func need(_ id: String) -> NSAccessibilityElement {
            guard let e = element(id) else { fail("\(id) not in the accessibility tree") }
            return e
        }
        func ids(_ prefix: String) -> [String] {
            elements().compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix(prefix) }
        }
        func footer() -> String {
            elements().compactMap { e -> String? in
                guard e.accessibilityRole() == .staticText, let l = e.accessibilityLabel(), l.hasSuffix(" left") else { return nil }
                return l
            }.first ?? ""
        }
        func press(_ id: String) {
            if !need(id).accessibilityPerformPress() { fail("AXPress on \(id) refused") }
            _ = settle()
        }
        func focusField() {
            need("^101").setAccessibilityFocused(true)
            let f = settle()
            if f.textInput?.control.label != "^101" { fail("the field is not focused after an AX focus") }
            if need("^101").isAccessibilityFocused() == false { fail("^101 is not AX-focused") }
        }
        func type(_ s: String) {
            view.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
            _ = settle()
        }
        func enter() {
            view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            _ = settle()
        }
        func expect(_ what: String, _ got: some Equatable, _ want: some Equatable) {
            if String(describing: got) != String(describing: want) { fail("\(what): \(got), expected \(want)") }
        }

        var f = settle()
        expect("first frame size", "\(f.size.w)x\(f.size.h)", "480x600")
        if need("^101").accessibilityRole() != .textField { fail("^101 is not a text field") }
        if need("^102").accessibilityRole() != .button { fail("^102 is not a button") }
        expect("items at start", ids("^10").filter { $0.hasPrefix("^103") || $0.hasPrefix("^104") }, [String]())
        expect("footer at start", footer(), "0 items left")

        // Click the field (an AX focus is a click at its centre), type, press Enter.
        focusField()
        type("  Buy milk ")
        expect("field text", view.engine.latest?.frame.textInput?.text ?? "", "  Buy milk ")
        enter()
        expect("checkboxes after Enter", ids("^103"), ["^103#1"])
        expect("delete buttons after Enter", ids("^104"), ["^104#1"])
        expect("item label (trimmed)", need("^103#1").accessibilityLabel() ?? "", "Buy milk")
        expect("field after Enter", engine.latest?.frame.textInput?.text ?? "", "")
        expect("footer after Enter", footer(), "1 item left")

        // Type again, then press Add.
        type("Eggs")
        press("^102")
        expect("checkboxes after Add", ids("^103"), ["^103#1", "^103#2"])
        expect("focus after Add", engine.latest?.frame.textInput == nil, true)
        expect("footer after Add", footer(), "2 items left")

        // Blank text adds nothing.
        focusField()
        type("   ")
        enter()
        press("^102")
        expect("checkboxes after blank adds", ids("^103"), ["^103#1", "^103#2"])

        // Toggle item 1: the checkbox's value and the footer follow.
        press("^103#1")
        expect("^103#1 value", need("^103#1").accessibilityValue() as? Int ?? -1, 1)
        expect("^103#2 value", need("^103#2").accessibilityValue() as? Int ?? -1, 0)
        expect("footer after toggle", footer(), "1 item left")

        // Delete item 2: both of its controls go, item 1 stays.
        press("^104#2")
        expect("checkboxes after delete", ids("^103"), ["^103#1"])
        expect("delete buttons after delete", ids("^104"), ["^104#1"])
        expect("footer after delete", footer(), "0 items left")

        // Tab moves keyboard focus in paint order: field, Add, then the item's controls.
        f = settle(engine.send([.pointerExit, .key(.tab, Mods())]))
        expect("focus after Tab", f.ax.first { $0.focused }?.control?.label ?? "none", "^101")
        f = settle(engine.send([.key(.tab, Mods())]))
        expect("focus after Tab Tab", f.ax.first { $0.focused }?.control?.label ?? "none", "^102")
        if view.shadowDivergences.count != 0 { fail("text shadow diverged: \(view.shadowDivergences)") }

        // The frame paints what it says: the Add button's fill, clear of its label.
        guard let add = f.ax.first(where: { $0.control?.label == "^102" }) else { fail("^102 not in frame") }
        do {
            let r = try Renderer()
            let c = try r.probe(f, at: Point(x: add.rect.x + 3, y: add.rect.y + add.rect.h / 2))
            expect("Add fill", "\(c.r),\(c.g),\(c.b)", "0,122,255")
        } catch { fail("render: \(error)") }

        engine.stop()
        print("selftest: PASS (Basics, v1: focus, type, Enter, Add, blank, toggle, delete, Tab, AX, paint)")
    }
}

/// Lean through the real exports and codec, with no threads: input → frame (encode events, step,
/// frame, decode) and the frame's size in bytes.
enum Bench {
    static func run() {
        LeanRuntime.enter(module: basics.module)
        let codec = FrameV1Codec()
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
            step(click(center(ax("^101"))))
            var adds: [Event] = []
            for i in 0..<n { adds += [.insertText("Item \(i + 1)"), .key(.enter, Mods())] }
            let t0 = hostNow()
            step(adds)
            let addMs = (hostNow() - t0) * 1000
            let (f, bytes) = frame()
            precondition(f.ax.filter { $0.control?.claim == 103 }.count == n)
            let toggle = center(ax("^103#1"))

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
                print(String(format: "  %@: p50 %.3f ms, p95 %.3f ms", label, ms[ms.count / 2], ms[ms.count * 95 / 100]))
            }
            print("\(n) items: frame \(bytes) bytes, \(f.draws.count) draws, \(f.ax.count) ax nodes; adding them took \(String(format: "%.1f", addMs)) ms")
            time("type one character (field focused)") { [.insertText("x")] }
            time("click a checkbox (move, down, up)") { click(toggle) }
            var x: Int32 = 0
            time("pointer move (hover)") { x = (x + 7) % 400; return [.pointerMove(Point(x: 20 + x, y: 300))] }
            cairn_lean_dec(state)
        }
    }
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Basics", size: size) { LeanCore(basics) })
}
