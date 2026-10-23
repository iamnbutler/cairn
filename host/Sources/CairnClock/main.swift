import AppKit
import CLean
import CairnCapture
import CairnFrame
import CairnHost
import Metal
import QuartzCore

// Clock (lean/Examples/Clock.lean): a stopwatch on time, timers, file requests and a
// subscription (docs/effects.md).
//   CairnClock               open the window
//   CairnClock --selftest    drive the host headlessly through its real threads and check it

let clock = LeanApp(
    module: runtime_initialize_cairn_Examples_Clock_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

let size = Size(w: 480, h: 520)
let args = CommandLine.arguments

if let code = MapCapture.main(args, size: size, core: { LeanCore(clock) }) { exit(code) }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

/// The standard handlers with `~/` sent to a scratch directory, so the self test never touches
/// the real laps file. (The handler table is the host's whole request surface.)
func scratchHandlers(_ home: String) -> Handlers {
    var h = Handlers.standard
    @Sendable func moved(_ p: String) -> String { p.hasPrefix("~/") ? home + String(p.dropFirst(1)) : p }
    let read = h.table[0]!, write = h.table[1]!
    h.table[0] = { r, reply in
        if case let .readFile(p) = r { read(.readFile(path: moved(p)), reply) }
    }
    h.table[1] = { r, reply in
        if case let .writeFile(p, d) = r { write(.writeFile(path: moved(p), data: d), reply) }
    }
    h.table[2] = { _, reply in reply(.done) }  // no sound in a headless test
    return h
}

@MainActor
enum SelfTest {
    static func run() {
        let home = NSTemporaryDirectory() + "cairn-clock-selftest-\(getpid())"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let engine = Engine(size: size, scalePercent: 200, world: World(handlers: scratchHandlers(home))) {
            LeanCore(clock)
        }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }

        func texts() -> [String] {
            engine.latest?.frame.draws.compactMap { if case let .text(_, _, _, s) = $0 { s } else { nil } } ?? []
        }
        /// Waits (up to `timeout` s) for a frame whose texts satisfy `ok`.
        func until(_ what: String, timeout: Double = 3, _ ok: ([String]) -> Bool) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while !ok(texts()) {
                if Date() > deadline { fail("\(what): texts \(texts())") }
                usleep(100)
            }
            view.applyLatestFrame()
        }
        func click(_ id: String) -> Double {
            guard let node = engine.latest?.frame.ax.first(where: { $0.control?.label == id }) else {
                fail("\(id) not in frame")
            }
            let c = Point(x: node.rect.x + node.rect.w / 2, y: node.rect.y + node.rect.h / 2)
            let t = hostNow()
            _ = engine.wait(through: engine.send([.pointerMove(c), .pointerDown(c, .primary, clicks: 1, Mods()),
                                                  .pointerUp(c, .primary, Mods())]))
            view.applyLatestFrame()
            return t
        }
        func reading() -> String { texts().first { $0.contains(":") && $0.contains(".") } ?? "" }

        // Launch: the first clock reads the (missing) laps file, quietly; the time-of-day
        // subscription is running.
        until("the time of day") { $0.contains { $0.hasPrefix("Time of day ") && $0 != "Time of day 00:00:00" } }
        let subDeadline = Date(timeIntervalSinceNow: 2)
        while engine.world.running != [1] {
            if Date() > subDeadline { fail("subscriptions \(engine.world.running), expected [1]") }
            usleep(1000)
        }

        // Start: the tick timer moves the reading with no input at all.
        _ = click("^401")
        until("the reading moves") { _ in reading() >= "0:00.3" }
        if engine.latest?.frame.wake == nil { fail("running with no wake") }

        // Lap, then Stop: the timer is cancelled and the reading stays put.
        _ = click("^402")
        _ = click("^401")
        let stopped = reading()
        if engine.latest?.frame.wake != nil { fail("stopped with a wake") }
        usleep(300_000)
        _ = engine.wait(through: engine.send([.pointerMove(Point(x: 1, y: 1))]))
        if reading() != stopped { fail("reading moved after Stop: \(stopped) → \(reading())") }

        // Save writes the file atomically; Reset, then Load reads it back.
        _ = click("^404")
        until("saved") { $0.contains("Saved 1 laps") }
        let file = home + "/Library/Application Support/Cairn/Clock/laps.txt"
        guard let saved = try? String(contentsOfFile: file, encoding: .utf8),
              saved.hasSuffix("\n"), Int(saved.dropLast()) != nil else { fail("laps file: \(String(describing: try? String(contentsOfFile: file, encoding: .utf8)))") }
        _ = click("^403")
        until("reset") { !$0.contains { $0.hasPrefix("Lap 1") } }
        _ = click("^405")
        until("loaded") { $0.contains("Loaded 1 laps") && $0.contains { $0.hasPrefix("Lap 1") } }

        // Request round trip: click Load → read → reply → frame with the status, measured.
        var trips: [Double] = []
        for i in 0..<40 {
            // Alternate the status so each load shows a change.
            if i % 2 == 0 {
                _ = click("^404")
                until("saved again") { $0.contains("Saved 1 laps") }
            }
            let t = click("^405")
            until("loaded again") { $0.contains("Loaded 1 laps") }
            trips.append((hostNow() - t) * 1000)
        }
        trips.sort()

        // Timer accuracy: how late after its deadline the clock that fires a tick arrives.
        _ = click("^403")
        _ = click("^401")
        var late: [Double] = []
        for _ in 0..<30 {
            guard let wake = engine.latest?.frame.wake else { fail("no wake while running") }
            while HostClock.monoMs() < wake + 50, engine.latest?.frame.wake == wake { usleep(500) }
            let now = HostClock.monoMs()
            if engine.latest?.frame.wake == wake { fail("tick at \(wake) never came") }
            late.append(Double(now) - Double(wake))
        }
        _ = click("^401")
        late.sort()
        engine.stop()
        func q(_ xs: [Double], _ p: Double) -> String { String(format: "%.2f", xs[min(xs.count - 1, Int(Double(xs.count) * p))]) }
        print("selftest: PASS (Clock: launch read, timer ticks, cancel on Stop, save/reset/load, subscription)")
        print("  request round trip (click → readFile → reply → frame), ms: p50 \(q(trips, 0.5)) p90 \(q(trips, 0.9)) max \(q(trips, 1))")
        print("  tick observed after its deadline (upper bound, 0.5 ms polling), ms: p50 \(q(late, 0.5)) p90 \(q(late, 0.9)) max \(q(late, 1))")
    }
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Clock", size: size) { LeanCore(clock) })
}
