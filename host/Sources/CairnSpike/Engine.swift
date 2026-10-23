import CLean
import Foundation

/// Calls into Lean. Every Lean argument is owned: a call consumes it.
enum Lean {
    static func initialize() { cairn_lean_init() }

    static func bytes(_ b: [UInt8]) -> OpaquePointer {
        b.withUnsafeBufferPointer { cairn_bytes_new($0.baseAddress, $0.count) }
    }

    /// Copies a Lean byte array out and releases it.
    static func take(_ o: OpaquePointer) -> Data {
        let d = Data(bytes: cairn_bytes_data(o), count: cairn_bytes_size(o))
        cairn_lean_dec(o)
        return d
    }
}

/// Owns the Lean state on a thread of its own. The main thread only enqueues events.
final class Engine: @unchecked Sendable {
    private let cond = NSCondition()
    private var pending: [UInt8] = []
    private var latest: Frame?
    private var version = 0
    private let width: UInt32, height: UInt32

    /// Called on the Lean thread after each new frame.
    var onFrame: ((Frame) -> Void)?
    /// Lean time for the last step + frame, in milliseconds.
    private(set) var lastLeanMs: Double = 0

    init(width: UInt32, height: UInt32) {
        self.width = width
        self.height = height
    }

    func start() {
        let t = Thread { [self] in run() }
        t.name = "cairn.lean"
        t.qualityOfService = .userInteractive
        t.start()
    }

    func send(_ events: [Event]) {
        cond.lock()
        for e in events { e.append(to: &pending) }
        cond.signal()
        cond.unlock()
    }

    func snapshot() -> (Frame?, Int) {
        cond.lock()
        defer { cond.unlock() }
        return (latest, version)
    }

    private func run() {
        cairn_lean_thread_begin()
        var state = cairn_counter_new(width, height)!
        publish(&state, ms: 0)
        while true {
            cond.lock()
            while pending.isEmpty { cond.wait() }
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            cond.unlock()

            let t0 = DispatchTime.now().uptimeNanoseconds
            state = cairn_counter_step(state, Lean.bytes(batch))
            publish(&state, ms: Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
    }

    private func publish(_ state: inout OpaquePointer, ms: Double) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        cairn_lean_inc(state)  // frame consumes its argument; keep ours
        let data = Lean.take(cairn_counter_frame(state))
        let leanMs = ms + Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        guard let frame = try? Frame(bytes: data) else {
            FileHandle.standardError.write("cairn: undecodable frame\n".data(using: .utf8)!)
            return
        }
        cond.lock()
        latest = frame
        version += 1
        lastLeanMs = leanMs
        cond.unlock()
        onFrame?(frame)
    }
}
