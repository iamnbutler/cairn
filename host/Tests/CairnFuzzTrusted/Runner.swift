import Foundation

/// One failing case of one check.
struct Failure {
    var check: String
    var caseIndex: Int
    var seed: UInt64
    var message: String
    var repro: String?

    var json: [String: Any] {
        var o: [String: Any] = ["case": caseIndex, "seed": String(seed), "message": message]
        if let repro { o["repro"] = repro }
        return o
    }
}

/// What a run learned about one check: how many cases evaluated it, and what failed.
struct CheckStats {
    var cases = 0
    var failingCases = 0
    var failures: [Failure] = []
    var counters: [String: Int] = [:]
    var seconds = 0.0

    mutating func merge(_ o: CheckStats) {
        cases += o.cases
        failingCases += o.failingCases
        failures += o.failures.prefix(max(0, Recorder.keep - failures.count))
        for (k, v) in o.counters { counters[k, default: 0] += v }
        seconds += o.seconds
    }

    var json: [String: Any] {
        ["cases": cases, "failingCases": failingCases, "failures": failures.map(\.json),
         "counters": counters, "seconds": seconds]
    }

    init() {}
    init(json o: [String: Any], check: String) {
        cases = o["cases"] as? Int ?? 0
        failingCases = o["failingCases"] as? Int ?? 0
        counters = o["counters"] as? [String: Int] ?? [:]
        seconds = o["seconds"] as? Double ?? 0
        failures = (o["failures"] as? [[String: Any]] ?? []).map {
            Failure(check: check, caseIndex: $0["case"] as? Int ?? -1,
                    seed: UInt64($0["seed"] as? String ?? "0") ?? 0,
                    message: $0["message"] as? String ?? "", repro: $0["repro"] as? String)
        }
    }
}

/// Collects results while a suite runs. A case fails a check at most once.
final class Recorder {
    static let keep = 10
    var checks: [String: CheckStats] = [:]
    var verbose = false
    var caseIndex = 0
    var caseSeed: UInt64 = 0
    private var failedThisCase: Set<String> = []
    private var evaluatedThisCase: Set<String> = []

    func begin(_ i: Int, seed: UInt64) {
        caseIndex = i; caseSeed = seed
        failedThisCase = []; evaluatedThisCase = []
    }

    /// The check was evaluated in this case.
    func ran(_ check: String) {
        if evaluatedThisCase.insert(check).inserted { checks[check, default: CheckStats()].cases += 1 }
    }

    func count(_ check: String, _ key: String, _ n: Int = 1) {
        checks[check, default: CheckStats()].counters[key, default: 0] += n
    }

    func fail(_ check: String, _ message: @autoclosure () -> String, repro: (() -> String?)? = nil) {
        ran(check)
        guard failedThisCase.insert(check).inserted else { return }
        var st = checks[check, default: CheckStats()]
        st.failingCases += 1
        if st.failures.count < Self.keep {
            let m = message()
            st.failures.append(Failure(check: check, caseIndex: caseIndex, seed: caseSeed, message: m, repro: repro?()))
            if verbose || st.failures.count <= 3 {
                FileHandle.standardError.write("FAIL \(check) case \(caseIndex): \(m.prefix(600))\n".data(using: .utf8)!)
            }
        }
        checks[check] = st
    }

    /// `check(cond, …)`: one evaluation of `check`, failing when `cond` is false.
    @discardableResult
    func expect(_ check: String, _ cond: Bool, _ message: @autoclosure () -> String, repro: (() -> String?)? = nil) -> Bool {
        if cond { ran(check) } else { fail(check, message(), repro: repro) }
        return cond
    }
}

/// A family of checks over one trusted boundary. Cases are numbered; case `i` of a run with seed
/// `S` uses the PRNG seeded with `S`, the suite's salt and `i`, so it replays alone.
protocol Suite: AnyObject {
    var name: String { get }
    /// The checks this suite reports, with what each one checks (for the JSON).
    var checks: [String: CheckInfo] { get }
    /// The check a crash of this suite is charged to.
    var crashCheck: String { get }
    /// How many cases a run of size N gives this suite (expensive suites take fewer).
    func cases(for n: Int) -> Int
    func setUp()
    func run(_ g: inout SplitMix, _ r: Recorder)
    /// What case `g` will do, without running the code under test (for a crash's repro).
    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String
}

struct CheckInfo {
    var title: String
    /// Which side is trusted, and checked: the Swift host, Core Text, AppKit.
    var trusted: [String]
    /// What it is checked against.
    var oracle: String
}

extension Suite {
    func caseSeed(_ seed: UInt64, _ i: Int) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return SplitMix.mix(seed ^ h) &+ UInt64(i)
    }
}

/// Runs suites, each in a child process so a crash in trusted code is a finding rather than the
/// end of the run: the child records the case it is on, and the parent charges a crash to that
/// case and restarts after it.
enum Runner {
    static func worker(_ suite: Suite, seed: UInt64, from: Int, to: Int, progress: URL, statsURL: URL, verbose: Bool) {
        suite.setUp()
        let fd = open(progress.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        let rec = Recorder()
        rec.verbose = verbose
        var lastFlush = Date()
        func flush(_ seconds: Double) {
            var out: [String: Any] = [:]
            for (k, var v) in rec.checks { v.seconds = seconds; out[k] = v.json }
            if let d = try? JSONSerialization.data(withJSONObject: out) { try? d.write(to: statsURL, options: .atomic) }
        }
        let start = Date()
        for i in from..<to {
            var idx = Int64(i)
            _ = pwrite(fd, &idx, 8, 0)
            let s = suite.caseSeed(seed, i)
            var g = SplitMix(seed: s)
            rec.begin(i, seed: s)
            autoreleasepool { suite.run(&g, rec) }
            if Date().timeIntervalSince(lastFlush) > 1 {
                flush(Date().timeIntervalSince(start))
                lastFlush = Date()
            }
        }
        flush(Date().timeIntervalSince(start))
        close(fd)
    }

    static func supervise(_ suite: Suite, n: Int, seed: UInt64, reproDir: URL, verbose: Bool) -> [String: CheckStats] {
        var total: [String: CheckStats] = [:]
        for k in suite.checks.keys { total[k] = CheckStats() }
        let count = suite.cases(for: n)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cairn-fuzz-\(getpid())-\(suite.name)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let progress = tmp.appendingPathComponent("progress"), stats = tmp.appendingPathComponent("stats.json")
        var from = 0
        var crashes = 0
        while from < count {
            try? FileManager.default.removeItem(at: stats)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            p.arguments = ["--worker", suite.name, "--seed", String(seed), "--from", String(from), "--to", String(count),
                           "--progress", progress.path, "--stats", stats.path] + (verbose ? ["-v"] : [])
            do { try p.run() } catch { fatalError("cannot start worker: \(error)") }
            p.waitUntilExit()
            if let d = try? Data(contentsOf: stats),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] {
                for (k, v) in o { total[k, default: CheckStats()].merge(CheckStats(json: v, check: k)) }
            }
            if p.terminationReason == .exit && p.terminationStatus == 0 { break }
            // Crashed (or exited with an error) on the case in `progress`.
            var at = from
            if let d = try? Data(contentsOf: progress), d.count == 8 {
                at = Int(d.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) })
            }
            let s = suite.caseSeed(seed, at)
            var g = SplitMix(seed: s)
            let what = suite.describe(&g, reproDir: reproDir, caseIndex: at)
            let how = p.terminationReason == .uncaughtSignal ? "signal \(p.terminationStatus)" : "exit \(p.terminationStatus)"
            var st = total[suite.crashCheck, default: CheckStats()]
            st.cases += 1
            st.failingCases += 1
            if st.failures.count < Recorder.keep {
                st.failures.append(Failure(check: suite.crashCheck, caseIndex: at, seed: s,
                                           message: "crashed (\(how)): \(what)", repro: nil))
            }
            total[suite.crashCheck] = st
            FileHandle.standardError.write("CRASH \(suite.crashCheck) case \(at) (\(how)): \(what.prefix(400))\n".data(using: .utf8)!)
            crashes += 1
            if crashes > 50 { break }
            from = at + 1
        }
        return total
    }
}
