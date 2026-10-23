import AppKit
import CLean
import CairnCapture
import CairnFrame
import CairnHost
import Metal
import QuartzCore

// Counter (lean/Examples/Counter.lean) on the v1 ABI.
//   CairnCounter               open the window (add --stats for latency, --latency N to measure)
//   CairnCounter --selftest    drive the host headlessly through its real threads and check it

let counter = LeanApp(
    module: runtime_initialize_cairn_Examples_Counter_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

let size = Size(w: 480, h: 320)
let args = CommandLine.arguments

// `--map-capture <script.json> <out dir>`: headless screenshots with pins for the map (docs/map.md).
if let code = MapCapture.main(args, size: size, core: { LeanCore(counter) }) { exit(code) }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

/// The headless check `make check` runs: the real engine (Lean thread, v1 codec), the real view
/// (input mapping, accessibility mirror), no window.
@MainActor
enum SelfTest {
    static func run() {
        let engine = Engine(size: size, scalePercent: 200) { LeanCore(counter) }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }

        func settle(_ seq: UInt64) -> Frame {
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
        func count() -> Int {
            guard let label = elements().compactMap({ e -> String? in
                      guard e.accessibilityRole() == .staticText, let l = e.accessibilityLabel(),
                            l.hasPrefix("Count: ") else { return nil }
                      return l
                  }).first,
                  let n = Int(label.dropFirst("Count: ".count)) else { fail("no count label") }
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
        print("selftest: PASS (Counter, v1: clicks, presence of ^2, AXPress, slide-off)")
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
    CairnApp.main(CairnApp.Config(title: "Counter", size: size) { LeanCore(counter) })
}
