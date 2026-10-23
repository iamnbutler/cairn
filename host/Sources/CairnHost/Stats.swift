import Foundation
import QuartzCore

/// Rolling latency samples, in milliseconds. Thread-safe.
public final class LatencyStats: @unchecked Sendable {
    public struct Summary: Sendable, CustomStringConvertible {
        public var count: Int
        public var p50, p95, p99, max: Double
        public var description: String {
            count == 0 ? "no samples"
                : String(format: "p50 %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.2f ms (n=%d)", p50, p95, p99, max, count)
        }
    }

    public enum Metric: String, CaseIterable, Sendable {
        /// Lean step + frame + Swift decode, per batch.
        case lean = "lean step+frame+decode"
        /// Oldest input in a batch → its frame decoded and published.
        case inputToFrame = "input → frame"
        /// Oldest input in a batch → the first frame that includes it on screen (Metal's
        /// presented time).
        case inputToPresent = "input → present"
    }

    private let lock = NSLock()
    private var samples: [Metric: [Double]] = [:]
    private var next: [Metric: Int] = [:]
    private let capacity: Int

    public init(capacity: Int = 4096) { self.capacity = capacity }

    public func record(_ m: Metric, ms: Double) {
        lock.lock()
        defer { lock.unlock() }
        var s = samples[m, default: []]
        if s.count < capacity {
            s.append(ms)
        } else {
            let i = next[m, default: 0]
            s[i] = ms
            next[m] = (i + 1) % capacity
        }
        samples[m] = s
    }

    public func summary(_ m: Metric) -> Summary {
        lock.lock()
        let s = samples[m, default: []].sorted()
        lock.unlock()
        guard !s.isEmpty else { return Summary(count: 0, p50: 0, p95: 0, p99: 0, max: 0) }
        func q(_ p: Double) -> Double { s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))] }
        return Summary(count: s.count, p50: q(0.5), p95: q(0.95), p99: q(0.99), max: s.last!)
    }

    public func reset() {
        lock.lock()
        samples = [:]
        next = [:]
        lock.unlock()
    }

    public var report: String {
        Metric.allCases.map { "\($0.rawValue): \(summary($0))" }.joined(separator: "\n")
    }
}

/// The host's clock: seconds on the same base as `NSEvent.timestamp` and Metal's presented time.
@inline(__always) public func hostNow() -> Double { CACurrentMediaTime() }
