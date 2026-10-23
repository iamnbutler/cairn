import AppKit
import CLean
import CairnCapture
import CairnFrame
import CairnHost
import CairnRender
import Metal
import QuartzCore

// TodoMVC (lean/Examples/Todo.lean), workstream I.
//   CairnTodo               open the window (add --stats for latency, --latency N to measure)
//   CairnTodo --selftest    drive the host headlessly through its real threads and check it
//   CairnTodo --bench       update + view + layout + encode (and decode) at 100, 1,000, 10,000 nodes

let todo = LeanApp(
    module: runtime_initialize_cairn_Examples_Todo,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

/// Fits twelve todos (Examples.Todo.View.height); the proofs cover any window at least
/// `minWidth` wide and `height s` tall.
let size = Size(w: 560, h: 720)
let args = CommandLine.arguments

// `--map-capture <script.json> <out dir>`: headless screenshots with pins for the map (docs/map.md).
if let code = MapCapture.main(args, size: size, core: { LeanCore(todo) }) { exit(code) }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func center(_ r: Rect) -> Point { Point(x: r.x + r.w / 2, y: r.y + r.h / 2) }

func click(_ p: Point) -> [Event] {
    [.pointerMove(p), .pointerDown(p, .primary, clicks: 1, Mods()), .pointerUp(p, .primary, Mods())]
}

/// What AppKit sends for a double click: a second down with clickCount 2 (assumption ^214).
func doubleClick(_ p: Point) -> [Event] {
    click(p) + [.pointerDown(p, .primary, clicks: 2, Mods()), .pointerUp(p, .primary, Mods())]
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
/// (text input client, accessibility mirror), no window and no foreground input. It types and
/// presses through the entry points AppKit and assistive apps use, sends a double click as the
/// events the host would, and checks the frame and the AX tree after each step.
@MainActor
enum SelfTest {
    static func run() {
        let engine = Engine(size: size, scalePercent: 200) { LeanCore(todo) }
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
        func frame() -> Frame { settle() }
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
        func node(_ id: String) -> AxNode {
            guard let n = frame().ax.first(where: { $0.control?.label == id }) else { fail("\(id) not in frame") }
            return n
        }
        func texts() -> [String] {
            elements().filter { $0.accessibilityRole() == .staticText }.compactMap { $0.accessibilityLabel() }
        }
        func press(_ id: String) {
            if !need(id).accessibilityPerformPress() { fail("AXPress on \(id) refused") }
            settle()
        }
        func send(_ es: [Event]) { settle(engine.send(es)) }
        func type(_ s: String) {
            view.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
            settle()
        }
        func key(_ sel: Selector) {
            view.doCommand(by: sel)
            settle()
        }
        func focused() -> String { frame().textInput?.control.label ?? "none" }
        func expect(_ what: String, _ got: some Equatable, _ want: some Equatable) {
            if String(describing: got) != String(describing: want) { fail("\(what): \(got), expected \(want)") }
        }

        // T5, T1: focus starts in the new-todo field; no list or footer yet.
        let f = settle()
        expect("first frame size", "\(f.size.w)x\(f.size.h)", "560x720")
        expect("focus at launch", focused(), "^202")
        if need("^202").accessibilityRole() != .textField { fail("^202 is not a text field") }
        expect("controls at start", f.ax.compactMap { $0.control?.label }, ["^202"])

        // T6, T7: Enter adds the trimmed text and clears the field; T8: blank adds nothing.
        type("  Buy milk ")
        key(#selector(NSResponder.insertNewline(_:)))
        type("   ")
        key(#selector(NSResponder.insertNewline(_:)))
        type("Eggs")
        key(#selector(NSResponder.insertNewline(_:)))
        expect("checkboxes", ids("^204"), ["^204#1", "^204#2"])
        expect("label (trimmed)", need("^204#1").accessibilityLabel() ?? "", "Buy milk")
        expect("field after Enter", frame().textInput?.text ?? "", "")
        expect("focus after Enter", focused(), "^202")
        if !texts().contains(" items left") || !texts().contains("2") { fail("counter: \(texts())") }

        // T19, T35, T37: complete one; the counter is singular and Clear completed appears.
        press("^204#1")
        expect("^204#1 value", need("^204#1").accessibilityValue() as? Int ?? -1, 1)
        if !texts().contains(" item left") { fail("counter after toggle: \(texts())") }
        _ = need("^211")

        // T21, T49: the delete button is in the tree without hover.
        expect("delete buttons", ids("^206"), ["^206#1", "^206#2"])

        // T20, T25, T28: double-click a title, replace the text, press Enter.
        send(doubleClick(center(node("^205#2").rect)))
        expect("focus in edit mode", focused(), "^207#2")
        expect("edit field text", frame().textInput?.text ?? "", "Eggs")
        if ids("^204").contains("^204#2") { fail("the checkbox stays in edit mode") }
        send([.selectAll])
        type(" Free-range eggs ")
        key(#selector(NSResponder.insertNewline(_:)))
        expect("title after edit", need("^204#2").accessibilityLabel() ?? "", "Free-range eggs")
        expect("focus after edit", focused(), "^202")

        // T31: Escape discards an edit, even an emptied one.
        send(doubleClick(center(node("^205#2").rect)))
        send([.selectAll, .key(.backspace, Mods())])
        key(#selector(NSResponder.cancelOperation(_:)))
        expect("title after Escape", need("^204#2").accessibilityLabel() ?? "", "Free-range eggs")
        expect("edit fields after Escape", ids("^207"), [String]())

        // T40, T42: Active lists only the active todo; Completed only the completed one.
        press("^209")
        expect("rows under Active", ids("^204"), ["^204#2"])
        expect("Active selected", node("^209").selected, true)
        press("^210")
        expect("rows under Completed", ids("^204"), ["^204#1"])
        press("^208")

        // T16: toggle all, twice.
        press("^203")
        expect("all completed", ids("^204").map { need($0).accessibilityValue() as? Int ?? -1 }, [1, 1])
        if !texts().contains("0") { fail("counter after toggle all: \(texts())") }
        press("^203")
        expect("all active", ids("^204").map { need($0).accessibilityValue() as? Int ?? -1 }, [0, 0])

        // T38: clear completed; T22: delete.
        press("^204#1")
        press("^211")
        expect("rows after clear", ids("^204"), ["^204#2"])
        if ids("^211").count != 0 { fail("Clear completed stays with nothing completed") }
        press("^206#2")
        expect("controls after the last delete", frame().ax.compactMap { $0.control?.label }, ["^202"])
        if view.shadowDivergences.count != 0 { fail("text shadow diverged: \(view.shadowDivergences)") }

        engine.stop()
        print("selftest: PASS (Todo, v1: launch focus, add, blank, toggle, double-click edit, Enter, Escape, filters, toggle all, clear, delete, AX)")
    }
}

/// Lean through the real exports and codec, with no threads. For 100, 1,000 and 10,000 nodes
/// (about 5 nodes per todo, so 20, 200 and 2,000 todos): one keystroke in the new-todo field and
/// one checkbox click, each timed as encode events → step (update, view, layout) → frame
/// (encode) → decode. The window is tall enough for every row, as the proofs require.
enum Bench {
    static func run() {
        LeanRuntime.enter(module: todo.module)
        let codec = FrameV1Codec()
        print("TodoMVC bench (release, LEAN_ABORT_ON_NONLINEAR=\(ProcessInfo.processInfo.environment["LEAN_ABORT_ON_NONLINEAR"] ?? "unset"))")
        for todos in [20, 200, 2000] {
            let h = UInt32(32 + 56 + 48 + 40 + 28 + 44 * todos)
            var state = cairn_app_init(UInt32(size.w), h, 200)!
            func step(_ es: [Event]) { state = cairn_app_step(state, LeanRuntime.bytes(codec.encode(es)))! }
            func frame() -> (Frame, Int) {
                cairn_lean_inc(state)
                return try! LeanRuntime.withBytes(cairn_app_frame(state)!) { (try codec.decodeFrame($0), $0.count) }
            }
            var adds: [Event] = []
            for i in 0..<todos { adds += [.insertText("Todo \(i + 1)"), .key(.enter, Mods())] }
            let t0 = hostNow()
            step(adds)
            let addMs = (hostNow() - t0) * 1000
            let (f, bytes) = frame()
            precondition(f.ax.filter { $0.control?.claim == 204 }.count == todos)
            guard let box = f.ax.first(where: { $0.control?.label == "^204#1" })?.rect else { fail("no ^204#1") }
            let toggle = center(box)

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
            print("  \(todos) todos: \(f.draws.count) draws, \(f.ax.count) ax nodes, frame \(bytes) bytes; adding them took \(String(format: "%.1f", addMs)) ms")
            time("type one character (field focused)") { [.insertText("x")] }
            time("click a checkbox (move, down, up)") { click(toggle) }
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
    CairnApp.main(CairnApp.Config(title: "todos", size: size) { LeanCore(todo) })
}
