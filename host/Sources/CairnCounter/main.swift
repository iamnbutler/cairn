import AppKit
import CLean
import CairnCapture
import CairnFrame
import CairnHost
import Metal
import QuartzCore

// The Counter example (lean/Examples/Counter.lean) in the Cairn host.
//   CairnCounter               open the window (add --stats for latency, --latency N to measure)
//   CairnCounter --selftest    drive the host headlessly through its real threads and check it
//   CairnCounter --bench       time Lean frames across the FFI at 100, 1k and 10k nodes

// Counter still speaks the spike's v0 boundary; it moves to the v1 ABI
// (`cairn_app_init(w, h, scalePercent)`, v1 codec) when workstreams C and E land.
let counter = LeanApp(
    module: runtime_initialize_cairn_Examples_Counter,
    initialize: { w, h, _ in cairn_counter_new(w, h) },
    step: { cairn_counter_step($0, $1) },
    frame: { cairn_counter_frame($0) },
    codec: SpikeV0Codec())

let args = CommandLine.arguments

// `--map-capture <script.json> <out dir>`: headless screenshots with pins for the map (docs/map.md).
if let code = MapCapture.main(args, size: Size(w: 480, h: 320), core: { LeanCore(counter) }) { exit(code) }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

if args.contains("--bench") {
    let codec = SpikeV0Codec()
    LeanRuntime.enter(module: runtime_initialize_cairn_Examples_Counter)
    for n: UInt32 in [100, 1000, 10000] {
        var lean = 0.0, decode = 0.0
        let reps = 50
        for i in 0..<(reps + 5) {
            let t0 = hostNow()
            let o = cairn_bench_frame(n)!
            let t1 = hostNow()
            let f = try! LeanRuntime.withBytes(o) { try codec.decodeFrame($0) }
            let t2 = hostNow()
            precondition(f.ax.count == Int(n))
            if i >= 5 {
                lean += (t1 - t0) * 1000
                decode += (t2 - t1) * 1000
            }
        }
        print(String(format: "%5d nodes: Lean %.3f ms, Swift decode %.3f ms per frame",
                     n, lean / Double(reps), decode / Double(reps)))
    }
    exit(0)
}


/// The headless check `make check` runs: the real engine (Lean thread), the real view (input
/// mapping, accessibility mirror), no window.
@MainActor
enum SelfTest {
    static func run() {
        let engine = Engine(size: Size(w: 480, h: 320), scalePercent: 200) { LeanCore(counter) }
        let view = HostView(engine: engine, renderer: NullRenderer(), size: NSSize(width: 480, height: 320))
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }

        func settle(_ seq: UInt64) -> Frame {
            guard let p = engine.wait(through: seq) else { fail("no frame through #\(seq)") }
            view.applyLatestFrame()
            return p.frame
        }
        func elements() -> [NSAccessibilityElement] {
            (view.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
        }
        func element(_ id: String) -> NSAccessibilityElement? {
            elements().first { $0.accessibilityIdentifier() == id }
        }
        func count() -> Int {
            guard let label = elements().first(where: { $0.accessibilityRole() == .staticText })?.accessibilityLabel(),
                  let n = Int(label.split(separator: " ").last ?? "") else { fail("no count label") }
            return n
        }
        func click(_ id: String) {
            guard let node = engine.latest?.frame.ax.first(where: { $0.control?.label == id }) else { fail("\(id) not in frame") }
            let c = Point(x: node.rect.x + node.rect.w / 2, y: node.rect.y + node.rect.h / 2)
            _ = settle(engine.send([.pointerMove(c), .pointerDown(c, .primary, clicks: 1, Mods()), .pointerUp(c, .primary, Mods())]))
        }

        _ = settle(engine.lastSeq)
        if element("^2") != nil { fail("^2 present at count 0") }
        click("^1"); click("^1"); click("^1")
        if count() != 3 { fail("count \(count()) after three clicks on ^1") }
        guard let reset = element("^2") else { fail("^2 absent at count 3") }
        if reset.accessibilityRole() != .button { fail("^2 is not a button") }

        // Elements are reused across frames: the same object for ^1 after a click.
        let inc = element("^1")
        click("^1")
        if element("^1") !== inc { fail("^1 element was recreated") }
        if count() != 4 { fail("count \(count()) after a fourth click") }

        // An accessibility press is a real click at the node's centre, through Lean.
        if !reset.accessibilityPerformPress() { fail("AXPress on ^2 refused") }
        _ = settle(engine.lastSeq)
        if count() != 0 { fail("count \(count()) after AXPress on ^2") }
        if element("^2") != nil { fail("^2 present after reset") }

        // A press that slides off the control does nothing.
        let n = engine.latest!.frame.ax.first { $0.control?.label == "^1" }!
        let c = Point(x: n.rect.x + n.rect.w / 2, y: n.rect.y + n.rect.h / 2)
        _ = settle(engine.send([.pointerDown(c, .primary, clicks: 1, Mods()),
                                .pointerMove(Point(x: c.x + 300, y: c.y)),
                                .pointerUp(Point(x: c.x + 300, y: c.y), .primary, Mods())]))
        if count() != 0 { fail("a press released off ^1 counted") }

        // Latency through the Lean thread: bursts of moves (coalesced) and clicks.
        engine.stats.reset()
        for i in 0..<500 {
            let p = Point(x: Int32(i % 400), y: 300)
            var seq = engine.send([.pointerMove(p)])
            if i % 10 == 0 { seq = engine.send([.pointerDown(p, .primary, clicks: 1, Mods()), .pointerUp(p, .primary, Mods())]) }
            if i % 5 == 0 { _ = engine.wait(through: seq) }
        }
        _ = settle(engine.lastSeq)
        engine.stop()
        print("selftest: PASS")
        print("  \(LatencyStats.Metric.lean.rawValue): \(engine.stats.summary(.lean))")
        print("  \(LatencyStats.Metric.inputToFrame.rawValue): \(engine.stats.summary(.inputToFrame))")
    }
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Counter", size: Size(w: 480, h: 320)) { LeanCore(counter) })
}
