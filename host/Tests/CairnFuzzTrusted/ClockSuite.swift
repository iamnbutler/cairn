import CairnFrame
import CairnHost
import Foundation

/// An app that only listens to the clock: it records every batch with the monotonic time it
/// arrived. `arm(d)` sets a timer `d` ms after the next batch's clock; its frame asks to be
/// woken then until a clock at or past it arrives (as Lean's runtime does with its earliest
/// armed timer; `d = 0` is a deadline that is already due).
final class WakeCore: AppCore, @unchecked Sendable {
    struct Batch { var events: [Event]; var arrived: UInt64; var wall: Int64 }
    private let lock = NSLock()
    private var batches: [Batch] = []
    private var target: UInt64?
    private var arming: UInt64?

    func start(size: Size, scalePercent: UInt32) {}

    func step(_ events: [Event]) {
        let now = HostClock.monoMs(), wall = Int64(Date().timeIntervalSince1970 * 1000)
        lock.withLock {
            batches.append(Batch(events: events, arrived: now, wall: wall))
            guard case let .clock(t)? = events.first else { return }
            if let w = target, t.mono >= w { target = nil }
            if let d = arming { target = t.mono + d; arming = nil }
        }
    }

    func frame() throws -> Frame {
        lock.withLock { Frame(size: Size(w: 10, h: 10), draws: [], wake: target) }
    }

    func arm(_ d: UInt64) { lock.withLock { arming = d } }
    func clear() { lock.withLock { target = nil } }
    var log: [Batch] { lock.withLock { batches } }
}

/// The host's clock and wake (Engine, HostClock) against what Lean's time proofs assume
/// (docs/effects.md):
///
/// - `clock.monotonic`: every batch starts with exactly one clock and has no other; its `mono`
///   never decreases from batch to batch, is not ahead of the monotonic clock when the batch
///   arrives, and is at most a few ms behind it; `wall` is the wall clock and `zone` the
///   current offset; and `HostClock.now()` read on several threads at once never runs back.
/// - `clock.wake`: a frame's `wake` brings a clock-only batch whose time is at or past the
///   deadline (never early), within a bound; a wake that is cleared or met brings no more.
final class ClockSuite: Suite {
    let name = "clock"
    let crashCheck = "clock.wake"
    let checks: [String: CheckInfo] = [
        "clock.monotonic": CheckInfo(
            title: "The host's clock is monotonic milliseconds",
            trusted: ["host/Sources/CairnHost/World.swift (HostClock)", "host/Sources/CairnHost/Engine.swift"],
            oracle: "clock_gettime(CLOCK_MONOTONIC) and Date read when each batch arrives"),
        "clock.wake": CheckInfo(
            title: "The host wakes Lean by `wake`",
            trusted: ["host/Sources/CairnHost/Engine.swift"],
            oracle: "the frame's wake deadline and the clock of the batch that answers it"),
    ]

    /// How late a wake may be before it is a failure (ms). Generous: `make check` runs other
    /// work at the same time; the typical lateness is in bench/effects.md.
    static let lateBound: UInt64 = 40

    func cases(for n: Int) -> Int { max(2, n / 20) }
    func setUp() {}

    func threads(_ g: inout SplitMix, _ r: Recorder) {
        let check = "clock.monotonic"
        let order = Locked<[UInt64]>([])
        let group = DispatchGroup()
        let lock = NSLock()
        for _ in 0..<g.range(2, 8) {
            DispatchQueue.global().async(group: group) {
                for _ in 0..<500 {
                    lock.lock()
                    let t = HostClock.now().mono
                    order.update { $0.append(t) }
                    lock.unlock()
                }
            }
        }
        group.wait()
        let ts = order.value
        let back = zip(ts, ts.dropFirst()).first { $0.1 < $0.0 }
        r.expect(check, back == nil, "HostClock.now() ran back from \(back?.0 ?? 0) to \(back?.1 ?? 0)")
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        threads(&g, r)
        let core = WakeCore()
        let engine = Engine(size: Size(w: 10, h: 10), scalePercent: 100) { core }
        engine.start()
        defer { engine.stop() }
        guard engine.wait(through: 0) != nil else { r.fail("clock.wake", "no first frame"); return }
        usleep(5000)  // the first clock-only batch (the app hears the time at launch)

        for _ in 0..<g.range(1, 4) {
            let d = UInt64(g.elem([0, 0, 1, 2, 5, 10, 17, 33, 80]))
            let clearing = g.chance(1, 4) && d >= 30
            core.arm(d)
            _ = engine.wait(through: engine.send([.pointerExit]))
            guard let target = core.frameTarget else { r.fail("clock.wake", "no wake armed for \(d) ms"); continue }
            if clearing {
                // Cleared before it is due: no wake, if the clearing frame came first.
                let at = core.log.count
                core.clear()
                _ = engine.wait(through: engine.send([.pointerExit]))
                let cleared = core.log.last?.arrived ?? .max
                usleep(UInt32(d + 30) * 1000)
                if cleared < target {
                    let woke = core.log.dropFirst(at).filter { $0.events.count == 1 }
                    r.expect("clock.wake", woke.isEmpty, "\(woke.count) wakes after the wake was cleared")
                    r.count("clock.wake", "cleared")
                }
                continue
            }
            let at = core.log.count
            let deadline = Date(timeIntervalSinceNow: Double(d + Self.lateBound + 200) / 1000)
            var wake: WakeCore.Batch?
            while Date() < deadline {
                wake = core.log.dropFirst(at).first { $0.events.count == 1 }
                if wake != nil { break }
                usleep(500)
            }
            guard let w = wake, case let .clock(t) = w.events[0] else {
                r.fail("clock.wake", "no wake for a deadline \(d) ms away")
                continue
            }
            r.expect("clock.wake", t.mono >= target, "woken at \(t.mono), \(target - t.mono) ms before the deadline \(target)")
            let late = t.mono >= target ? t.mono - target : 0
            r.count("clock.wake", late == 0 ? "late0ms" : late <= 1 ? "late1ms" : late <= 5 ? "late2to5ms" : "lateOver5ms")
            r.expect("clock.wake", late <= Self.lateBound, "woken \(late) ms after the deadline")
            // Met: no more wakes for it.
            let n = core.log.count
            usleep(20_000)
            let extra = core.log.dropFirst(n).filter { $0.events.count == 1 }
            r.expect("clock.wake", extra.isEmpty, "\(extra.count) more wakes after the deadline was met")
        }

        // Every batch: one clock, first; mono never decreasing, not ahead of arrival, at most a
        // few ms behind it; wall and zone current.
        var last: UInt64 = 0
        let zone = Int32(TimeZone.current.secondsFromGMT())
        for b in core.log {
            let clocks = b.events.filter { if case .clock = $0 { true } else { false } }
            guard clocks.count == 1, case let .clock(t) = b.events[0] else {
                r.fail("clock.monotonic", "a batch with \(clocks.count) clocks: \(b.events)")
                continue
            }
            r.expect("clock.monotonic", t.mono >= last, "the clock ran back from \(last) to \(t.mono)")
            r.expect("clock.monotonic", t.mono <= b.arrived && b.arrived - t.mono <= Self.lateBound,
                     "clock \(t.mono) for a batch that arrived at \(b.arrived)")
            r.expect("clock.monotonic", abs(t.wall - b.wall) <= 1000, "wall \(t.wall), Date \(b.wall)")
            r.expect("clock.monotonic", t.zone == zone, "zone \(t.zone), current \(zone)")
            last = t.mono
        }
        r.count("clock.monotonic", "batches", core.log.count)
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "Engine wake and clock with a WakeCore"
    }
}

extension WakeCore {
    /// The deadline the next frame will carry.
    var frameTarget: UInt64? { (try? frame())?.wake }
}
