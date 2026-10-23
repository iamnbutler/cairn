import CairnFrame
import Foundation
import Testing

/// `make bench-frame` (CAIRN_BENCH=1, release): decode time for the 1,000- and 10,000-node frames
/// `framecorpus bench` wrote. Skipped in normal test runs.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CAIRN_BENCH"] == "1"))
struct DecodeBench {
    @Test func decode() throws {
        for n in [1000, 10000] {
            let bytes = try Corpus.bytes(Corpus.root.appendingPathComponent("bench/\(n).bin"))
            let reps = 200
            var best = Double.infinity, total = 0.0
            var draws = 0, ax = 0
            try bytes.withUnsafeBytes { raw in
                for i in 0..<(reps + 20) {
                    let t0 = DispatchTime.now().uptimeNanoseconds
                    let f = try Frame(decoding: raw)
                    let t = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                    draws = f.draws.count; ax = f.ax.count
                    if i >= 20 { total += t; best = min(best, t) }
                }
                print(String(format: "%d nodes (%d bytes, %d draws, %d ax): decode %.3f ms mean, %.3f ms best",
                             n, bytes.count, draws, ax, total / Double(reps), best))
            }
        }
    }
}
