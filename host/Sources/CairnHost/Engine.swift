import CairnFrame
import Foundation

/// A decoded frame and what it accounts for.
public struct Published: Sendable {
    public let frame: Frame
    /// Increases by one per published frame.
    public let version: Int
    /// Every event `send` numbered at or below this has been stepped into this frame.
    public let throughSeq: UInt64
    /// The oldest input time (`hostNow()` base) among the events this frame was the first to
    /// include, if any.
    public let inputTime: Double?
}

/// Owns the app on a thread of its own (the Lean thread). Other threads only enqueue events and
/// read the latest published frame; nothing here ever waits on Lean except `wait(through:)`,
/// which is for tests.
///
/// The Lean thread loops: wait for events, take the whole queue, encode it, `step`, `frame`,
/// decode, publish. Events that arrive while Lean is busy form the next batch, so a slow step
/// batches input instead of falling behind. Consecutive pointer moves are coalesced in the
/// queue (only the latest position matters), and so are consecutive scrolls (deltas summed).
public final class Engine: @unchecked Sendable {
    private struct Pending {
        var event: Event
        var seq: UInt64
        var time: Double
    }

    private let cond = NSCondition()
    private var queue: [Pending] = []
    private var nextSeq: UInt64 = 1
    private var latestPublished: Published?
    private var effects: [Effect] = []
    private var unpresented: [(version: Int, time: Double)] = []
    private var running = false
    private var stopping = false

    private let makeCore: () -> AppCore
    private let initialSize: Size
    private let initialScale: UInt32

    public let stats = LatencyStats()

    /// `CAIRN_LOG_EVENTS=1` logs every event sent to stderr.
    static let logEvents = ProcessInfo.processInfo.environment["CAIRN_LOG_EVENTS"] != nil

    /// Called on the Lean thread after each publish. Keep it short: hop to another queue.
    public var onPublish: (@Sendable (Published) -> Void)?

    /// - Parameter makeCore: builds the app; called on the Lean thread, so a Lean app's runtime
    ///   initialization happens there and the main thread never calls Lean at all.
    public init(size: Size, scalePercent: UInt32, makeCore: @escaping () -> AppCore) {
        self.makeCore = makeCore
        self.initialSize = size
        self.initialScale = scalePercent
    }

    public func start() {
        cond.lock()
        guard !running else { cond.unlock(); return }
        running = true
        cond.unlock()
        let t = Thread { [self] in run() }
        t.name = "cairn.lean"
        t.qualityOfService = .userInteractive
        t.stackSize = 64 << 20  // Lean recursion on deep trees
        t.start()
    }

    /// Asks the Lean thread to finish after its current batch.
    public func stop() {
        cond.lock()
        stopping = true
        cond.broadcast()
        cond.unlock()
    }

    /// Enqueues events and returns the sequence number of the last one (or of the last event
    /// sent, if `events` is empty). Never blocks on Lean.
    @discardableResult
    public func send(_ events: [Event], time: Double = hostNow()) -> UInt64 {
        if Self.logEvents { for e in events { FileHandle.standardError.write("cairn event: \(e)\n".data(using: .utf8)!) } }
        cond.lock()
        defer { cond.unlock() }
        for e in events {
            let seq = nextSeq
            nextSeq += 1
            if var last = queue.last, let merged = Self.coalesce(last.event, e) {
                last.event = merged
                last.seq = seq
                queue[queue.count - 1] = last  // keeps the older time: latency counts from it
            } else {
                queue.append(Pending(event: e, seq: seq, time: time))
            }
        }
        if !events.isEmpty { cond.broadcast() }  // test waiters share the condition
        return nextSeq - 1
    }

    /// The event that replaces `a` followed by `b`, when the pair can be merged.
    static func coalesce(_ a: Event, _ b: Event) -> Event? {
        switch (a, b) {
        case (.pointerMove, .pointerMove(let p)): return .pointerMove(p)
        case let (.scroll(_, dx0, dy0), .scroll(p, dx1, dy1)):
            return .scroll(p, dx: dx0 &+ dx1, dy: dy0 &+ dy1)
        default: return nil
        }
    }

    /// The newest frame, if Lean has produced one. Cheap; safe from any thread.
    public var latest: Published? {
        cond.lock()
        defer { cond.unlock() }
        return latestPublished
    }

    /// The highest sequence number handed out so far.
    public var lastSeq: UInt64 {
        cond.lock()
        defer { cond.unlock() }
        return nextSeq - 1
    }

    /// Takes the effects of every frame published since the last call, in order.
    public func takeEffects() -> [Effect] {
        cond.lock()
        defer { cond.unlock() }
        let e = effects
        effects.removeAll()
        return e
    }

    /// Blocks until a frame includes event `seq`. Tests and tools only; the host never waits.
    public func wait(through seq: UInt64, timeout: Double = 5) -> Published? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        cond.lock()
        defer { cond.unlock() }
        while (latestPublished?.throughSeq ?? 0) < seq || latestPublished == nil {
            if !cond.wait(until: deadline) { return nil }
        }
        return latestPublished
    }

    /// The render thread reports that `version` reached the screen at `time`. Records
    /// input → present for it and every earlier version that was never drawn on its own.
    public func presented(version: Int, at time: Double) {
        cond.lock()
        var done: [Double] = []
        unpresented.removeAll { v in
            if v.version <= version { done.append(v.time); return true }
            return false
        }
        cond.unlock()
        for t in done { stats.record(.inputToPresent, ms: (time - t) * 1000) }
    }

    private func run() {
        let core = makeCore()
        core.start(size: initialSize, scalePercent: initialScale)
        publish(core, throughSeq: 0, inputTime: nil, stepMs: 0)
        while true {
            cond.lock()
            while queue.isEmpty && !stopping { cond.wait() }
            if stopping { cond.unlock(); break }
            let batch = queue
            queue.removeAll(keepingCapacity: true)
            cond.unlock()

            let t0 = hostNow()
            core.step(batch.map(\.event))
            let stepMs = (hostNow() - t0) * 1000
            publish(core, throughSeq: batch.last!.seq, inputTime: batch.map(\.time).min(), stepMs: stepMs)
        }
    }

    private var version = 0

    private func publish(_ core: AppCore, throughSeq: UInt64, inputTime: Double?, stepMs: Double) {
        let t0 = hostNow()
        let frame: Frame
        do {
            frame = try core.frame()
        } catch {
            FileHandle.standardError.write("cairn: undecodable frame (\(error)); keeping the last one\n".data(using: .utf8)!)
            return
        }
        let t1 = hostNow()
        stats.record(.lean, ms: stepMs + (t1 - t0) * 1000)
        if let inputTime { stats.record(.inputToFrame, ms: (t1 - inputTime) * 1000) }
        version += 1
        let p = Published(frame: frame, version: version, throughSeq: throughSeq, inputTime: inputTime)
        cond.lock()
        latestPublished = p
        effects += frame.effects
        if let inputTime { unpresented.append((version, inputTime)) }
        if unpresented.count > 256 { unpresented.removeFirst(unpresented.count - 256) }
        cond.broadcast()
        cond.unlock()
        onPublish?(p)
    }
}
