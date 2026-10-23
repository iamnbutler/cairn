import AppKit
import Foundation

// cairn-fuzz-trusted: fuzzes the trusted base (docs/fuzz.md, "Trusted base", docs/trusted.md).
//
//   CairnFuzzTrusted [--n N] [--seed S] [--only frame,events,…] [--out build/fuzz/trusted.json]
//                    [--claims claims.json] [-v]
//   CairnFuzzTrusted --replay SUITE --case I [--seed S]   run one case in this process, verbosely
//
// Each suite runs in a child process (`--worker`), so a crash in trusted code is reported with
// its case instead of ending the run. Exit status 1 when any check failed.
//
// --claims reads `lake exe claims Cairn.Fuzz.Trusted.Claims` and lists, under each check, the
// `assume` claims that name it (`check "…"`); a claim naming a check no suite has is an error.

setvbuf(stdout, nil, _IOLBF, 0)

let allSuites: [Suite] = [FrameSuite(), EventsSuite(), TextIndexSuite(), InputClientSuite(), MetricsSuite()]

var args = Array(CommandLine.arguments.dropFirst())
func take(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let verbose = args.contains("-v")
let seed = UInt64(take("--seed") ?? ProcessInfo.processInfo.environment["SEED"] ?? "0") ?? 0

func suite(_ name: String) -> Suite {
    guard let s = allSuites.first(where: { $0.name == name }) else {
        FileHandle.standardError.write("no suite \(name); suites: \(allSuites.map(\.name).joined(separator: ", "))\n".data(using: .utf8)!)
        exit(2)
    }
    return s
}

// Some suites drive AppKit (HostView); they need the shared application, never shown.
_ = MainActor.assumeIsolated { NSApplication.shared }

if let w = take("--worker") {
    let s = suite(w)
    Runner.worker(s, seed: seed, from: Int(take("--from")!)!, to: Int(take("--to")!)!,
                  progress: URL(fileURLWithPath: take("--progress")!), statsURL: URL(fileURLWithPath: take("--stats")!),
                  verbose: verbose)
    exit(0)
}

if let name = take("--replay") {
    let s = suite(name)
    let i = Int(take("--case") ?? "0")!
    s.setUp()
    let r = Recorder()
    r.verbose = true
    let cs = s.caseSeed(seed, i)
    var g = SplitMix(seed: cs)
    r.begin(i, seed: cs)
    var d = SplitMix(seed: cs)
    print("case \(i): \(s.describe(&d, reproDir: URL(fileURLWithPath: "build/fuzz/trusted"), caseIndex: i))")
    s.run(&g, r)
    for (k, v) in r.checks.sorted(by: { $0.key < $1.key }) {
        print("\(k): \(v.failingCases == 0 ? "pass" : "FAIL") \(v.counters)")
        for f in v.failures { print("  \(f.message)\n  \(f.repro ?? "")") }
    }
    exit(r.checks.values.contains { $0.failingCases > 0 } ? 1 : 0)
}

let n = Int(take("--n") ?? ProcessInfo.processInfo.environment["N"] ?? "1000") ?? 1000
let out = URL(fileURLWithPath: take("--out") ?? "build/fuzz/trusted.json")
let only = take("--only").map { Set($0.split(separator: ",").map(String.init)) }
let reproDir = out.deletingLastPathComponent().appendingPathComponent("trusted")

/// check name → the claims (`^901`) that name it.
var claimsByCheck: [String: [String]] = [:]
if let path = take("--claims") {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let known = Set(allSuites.flatMap { $0.checks.keys })
    for c in doc?["claims"] as? [[String: Any]] ?? [] {
        guard let check = c["check"] as? String, let ref = c["ref"] as? String else { continue }
        guard known.contains(check) else {
            FileHandle.standardError.write("claims: \(ref) names check \(check), which no suite has; checks: \(known.sorted().joined(separator: ", "))\n".data(using: .utf8)!)
            exit(2)
        }
        claimsByCheck[check, default: []].append(ref)
    }
}

var report: [String: Any] = [:]
var failed = false
let t0 = Date()
for s in allSuites where only?.contains(s.name) ?? true {
    let start = Date()
    let stats = Runner.supervise(s, n: n, seed: seed, reproDir: reproDir, verbose: verbose)
    let wall = Date().timeIntervalSince(start)
    for (check, info) in s.checks.sorted(by: { $0.key < $1.key }) {
        let st = stats[check] ?? CheckStats()
        let pass = st.failingCases == 0
        failed = failed || !pass
        var o = st.json
        o["title"] = info.title
        o["trusted"] = info.trusted
        o["oracle"] = info.oracle
        o["suite"] = s.name
        o["claims"] = claimsByCheck[check] ?? []
        o["pass"] = st.cases == 0 ? NSNull() : pass as Any
        o["casesPerSecond"] = st.seconds > 0 ? Double(st.cases) / st.seconds : 0
        o["evidence"] = st.cases == 0 ? "not run"
            : pass ? "held in \(st.cases) cases" : "failed in \(st.failingCases) of \(st.cases) cases"
        report[check] = o
        print(String(format: "%-22@ %@ %8d cases %6.1fs %@", check as NSString,
                     (pass ? "pass" : "FAIL") as NSString, st.cases, wall, (st.counters.isEmpty ? "" : "\(st.counters)") as NSString))
    }
}
let doc: [String: Any] = [
    "version": 1, "seed": String(seed), "n": n, "seconds": Date().timeIntervalSince(t0),
    "date": ISO8601DateFormatter().string(from: Date()),
    "checks": report,
]
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]).write(to: out)
print("wrote \(out.path)")
exit(failed ? 1 : 0)
