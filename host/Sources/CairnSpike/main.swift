import AppKit
import CLean

// The boundary spike: a Lean counter in a Swift window painted by Metal.
//   CairnSpike             open the window
//   CairnSpike --selftest  click through Lean without a window and check the results
//   CairnSpike --bench     time Lean frames across the FFI at 100, 1k and 10k nodes

Lean.initialize()
let args = CommandLine.arguments

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

if args.contains("--selftest") {
    cairn_lean_thread_begin()
    var state = cairn_counter_new(480, 320)!
    func frame() -> Frame {
        cairn_lean_inc(state)
        return try! Frame(bytes: Lean.take(cairn_counter_frame(state)))
    }
    func click(_ claim: UInt32) {
        guard let node = frame().nodes.first(where: { $0.claim == claim }) else { fail("^\(claim) not in frame") }
        var bytes: [UInt8] = []
        Event.down(node.center.0, node.center.1).append(to: &bytes)
        Event.up(node.center.0, node.center.1).append(to: &bytes)
        state = cairn_counter_step(state, Lean.bytes(bytes))
    }
    func has(_ claim: UInt32) -> Bool { frame().nodes.contains { $0.claim == claim } }
    func count() -> UInt32 { cairn_lean_inc(state); return cairn_counter_count(state) }

    if has(2) { fail("^2 present at count 0") }
    click(1); click(1); click(1)
    if count() != 3 { fail("count \(count()) after three clicks on ^1") }
    if !has(2) { fail("^2 absent at count 3") }
    click(2)
    if count() != 0 { fail("count \(count()) after ^2") }
    if has(2) { fail("^2 present after reset") }
    // A press that slides off the control does nothing.
    let n = frame().nodes.first { $0.claim == 1 }!
    var bytes: [UInt8] = []
    Event.down(n.center.0, n.center.1).append(to: &bytes)
    Event.up(n.x + n.w + 50, n.center.1).append(to: &bytes)
    state = cairn_counter_step(state, Lean.bytes(bytes))
    if count() != 0 { fail("a press released off ^1 counted") }
    cairn_lean_dec(state)
    print("selftest: PASS")
    exit(0)
}

if args.contains("--bench") {
    cairn_lean_thread_begin()
    for n: UInt32 in [100, 1000, 10000] {
        var lean = 0.0, decode = 0.0
        let reps = 50
        for i in 0..<(reps + 5) {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let data = Lean.take(cairn_bench_frame(n))
            let t1 = DispatchTime.now().uptimeNanoseconds
            let f = try! Frame(bytes: data)
            let t2 = DispatchTime.now().uptimeNanoseconds
            precondition(f.nodes.count == Int(n))
            if i >= 5 {
                lean += Double(t1 - t0) / 1e6
                decode += Double(t2 - t1) / 1e6
            }
        }
        print(String(format: "%5d nodes: Lean %.3f ms, Swift decode %.3f ms per frame",
                     n, lean / Double(reps), decode / Double(reps)))
    }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        let size = NSSize(width: 480, height: 320)
        let engine = Engine(width: UInt32(size.width), height: UInt32(size.height))
        let view = HostView(engine: engine, size: size)
        engine.onFrame = { frame in DispatchQueue.main.async { view.mirror(frame) } }
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Cairn spike"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        do { view.start(renderer: try Renderer()) } catch { fatalError("Metal: \(error)") }
        engine.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
