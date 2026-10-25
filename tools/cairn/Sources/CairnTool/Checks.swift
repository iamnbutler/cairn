import Foundation

/// A command's arguments: `--name value` options, bare flags and positionals, against what the
/// command accepts. An option may repeat (`--product A --product B`).
public struct Arguments: Equatable, Sendable {
    public var options: [String: [String]] = [:]
    public var flags: Set<String> = []
    public var positionals: [String] = []

    public init(_ args: [String], options known: Set<String>, flags knownFlags: Set<String> = [], usage: String) throws(CairnError) {
        var rest = args[...]
        while let a = rest.popFirst() {
            if known.contains(a) {
                guard let v = rest.popFirst() else { throw CairnError("\(a) needs a value\n\(usage)") }
                options[a, default: []].append(v)
            } else if knownFlags.contains(a) {
                flags.insert(a)
            } else if a.hasPrefix("-") {
                throw CairnError("unknown option \(a)\n\(usage)")
            } else {
                positionals.append(a)
            }
        }
    }

    public func value(_ name: String) -> String? { options[name]?.last }

    /// A non-negative number, if given.
    public func number(_ name: String) throws(CairnError) -> Int? {
        guard let v = value(name) else { return nil }
        guard let n = Int(v), n >= 0 else { throw CairnError("\(name) takes a number, not `\(v)`") }
        return n
    }
}

extension Project {
    /// Whether the lakefile declares the executable `name` (`lean_exe fuzz`, `[[lean_exe]] name = "fuzz"`).
    public func declaresExe(_ name: String) -> Bool {
        guard let (lakefile, _) = try? Lakefile.load(lean) else { return false }
        switch lakefile.format {
        case .lean:
            return lakefile.text.split(separator: "\n").contains { line in
                let words = line.split(separator: " ", omittingEmptySubsequences: true)
                return words.count >= 2 && words[0] == "lean_exe" && (words[1] == name || words[1] == "«\(name)»")
            }
        case .toml:
            return lakefile.text.contains("name = \"\(name)\"")
        }
    }

    /// The app's Lean module root: the first of cairn.toml's `libs` (`Fixture`, `Yap`).
    public var appModule: String? { manifest.libs.first }

    /// The C name of a module's initializer in this package, as the module system emits it:
    /// `runtime_initialize_fixture_Fixture_Conformance`. Lean doubles `_` inside a name's
    /// components (`Template.mangled`).
    public func initializer(of module: String) -> String {
        "runtime_initialize_" + Template.mangled(manifest.name) + "_"
            + module.split(separator: ".").map { Template.mangled(String($0)) }.joined(separator: "_")
    }
}

/// `swift package describe`'s executable products, from its JSON.
enum SwiftPackage {
    static func executables(_ json: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let products = root["products"] as? [[String: Any]] else { return [] }
        return products.compactMap { p in
            guard let name = p["name"] as? String, let type = p["type"] as? [String: Any], type.keys.contains("executable") else { return nil }
            return name
        }
    }
}

/// The per-app tools: Cairn's checks, run on any app package the way `cairn build` builds one
/// (docs/cli.md, "Checks"). Cairn's own `make check` runs them on test/fixture.
extension Commands {
    /// The app's executable: `--product`, else the only executable product of its Package.swift.
    func product(_ project: Project, _ a: Arguments) throws(CairnError) -> [String] {
        if let given = a.options["--product"] { return given }
        guard FileManager.default.fileExists(atPath: project.swift.appending(path: "Package.swift").path) else {
            throw CairnError("\(project.manifest.name) has no Package.swift; this command runs an app's host")
        }
        let out = try shell.capture(["swift", "package", "describe", "--type", "json"], in: project.swift)
        let exes = SwiftPackage.executables(out.stdout)
        guard exes.count == 1 else {
            throw CairnError(exes.isEmpty ? "Package.swift has no executable product" : "Package.swift has several executables (\(exes.joined(separator: ", "))); pick one with --product")
        }
        return exes
    }

    func binPath(_ project: Project, release: Bool) throws(CairnError) -> URL {
        URL(filePath: try shell.capture(["swift", "build"] + (release ? ["-c", "release"] : []) + ["--show-bin-path"], in: project.swift).text)
    }

    /// A path the person gave, against the directory they ran `cairn` in.
    func path(_ p: String) -> URL {
        (p.hasPrefix("/") ? URL(filePath: p) : cwd.appending(path: p)).standardizedFileURL
    }

    func mkdir(_ url: URL) throws(CairnError) {
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch { throw CairnError("couldn't create \(url.path)") }
    }

    /// The Lake environment for tools that import modules from the build directory (`claims`):
    /// the artifact cache off, as `cairn doc` has it.
    func importEnv() -> [String: String] {
        var env = lakeEnv(registry())
        env["LAKE_ARTIFACT_CACHE"] = "false"
        return env
    }

    // MARK: fuzz

    /// `cairn fuzz [<target>…] [--iterations N] [--seed S] [--steps K] [--out DIR] [-v]`: Cairn's
    /// claim-driven fuzzer (docs/fuzz.md) on every fuzzable machine of the package, or the ones
    /// named, writing `<out>/<target>.json` (default build/fuzz/). The package declares the
    /// executable, as test/fixture does: `lean_exe fuzz` with a root that imports the app and
    /// `Cairn.Fuzz.Collect` and `Cairn.Fuzz.Main`, and defines `main` over `fuzz_targets%`.
    public func fuzz(_ args: [String]) throws(CairnError) {
        let usage = "usage: cairn fuzz [<target>…] [--iterations N] [--seed S] [--steps K] [--out DIR] [-v]"
        let a = try Arguments(args, options: ["--iterations", "--seed", "--steps", "--out"], flags: ["-v"], usage: usage)
        let project = try project()
        try project.agree()
        guard project.declaresExe("fuzz") else {
            throw CairnError("the lakefile declares no `lean_exe fuzz`; see docs/fuzz.md, \"An app package\", or Cairn's test/fixture/lean")
        }
        let env = lakeEnv(registry())
        try shell.run(["lake", "build", "fuzz"], in: project.lean, env: env)
        let exe = project.lean.appending(path: ".lake/build/bin/fuzz").path
        var targets = a.positionals
        if targets.isEmpty {
            targets = try shell.capture([exe, "--list"], in: project.lean).text
                .split(separator: "\n").compactMap { $0.split(separator: "\t").first.map(String.init) }
            guard !targets.isEmpty else { throw CairnError("the fuzzer found no machine in \(project.manifest.name)") }
        }
        let out = a.value("--out").map(path) ?? project.root.appending(path: "build/fuzz")
        var passthrough: [String] = []
        for o in ["--iterations", "--seed", "--steps"] { if let v = a.value(o) { passthrough += [o, v] } }
        if a.flags.contains("-v") { passthrough.append("-v") }
        var failed: [String] = []
        for t in targets {
            do { try shell.run([exe, t] + passthrough + ["--out", out.path], in: project.lean) } catch { failed.append(t) }
        }
        guard failed.isEmpty else { throw CairnError("fuzzing failed: \(failed.joined(separator: ", ")) (reports in \(out.path))") }
    }

    // MARK: claims

    /// `cairn claims [<module>…] [--out FILE]`: every claim of the package's `libs` (or the modules
    /// named) as JSON, `lake exe claims`, for the map, the conformance driver and `cairn doc`.
    public func claims(_ args: [String]) throws(CairnError) {
        let a = try Arguments(args, options: ["--out"], usage: "usage: cairn claims [<module>…] [--out FILE]")
        let project = try project()
        let modules = a.positionals.isEmpty ? project.documented : a.positionals
        guard !modules.isEmpty else { throw CairnError("cairn.toml lists no `libs`; name the modules") }
        let env = importEnv()
        try shell.run(["lake", "build"], in: project.lean, env: env)
        let json = try shell.capture(["lake", "exe", "claims"] + modules, in: project.lean, env: env)
        if let out = a.value("--out") {
            let url = path(out)
            try mkdir(url.deletingLastPathComponent())
            do { try json.stdout.write(to: url) } catch { throw CairnError("couldn't write \(url.path)") }
        } else {
            FileHandle.standardOutput.write(json.stdout)
        }
    }

    // MARK: bench

    /// `cairn bench [--product P]`: a release build, then the app's own `--bench` with
    /// LEAN_ABORT_ON_NONLINEAR=1, so an array copied on every write aborts instead of running slow
    /// (AGENTS.md, "Performance"). The host defines what `--bench` measures; test/fixture's is
    /// input → frame at 10 and 1,000 items.
    public func bench(_ args: [String]) throws(CairnError) {
        let a = try Arguments(args, options: ["--product"], usage: "usage: cairn bench [--product P]")
        let project = try project()
        let products = try product(project, a)
        try buildLean(project)
        for p in products { try shell.run(["swift", "build", "-c", "release", "--product", p], in: project.swift) }
        let bin = try binPath(project, release: true)
        for p in products {
            try shell.run([bin.appending(path: p).path, "--bench"], in: project.root, env: ["LEAN_ABORT_ON_NONLINEAR": "1"])
        }
    }

    // MARK: size

    /// `cairn size [--product P]… [--limit BYTES]`: each executable built for release with a link
    /// map, stripped into build/size/, its bytes attributed (Lean runtime, Cairn, the app, Swift
    /// host, shaders) by Cairn's tools/size/size.ts, and checked against the limit (default
    /// 5,000,000 bytes; crossing it almost always means something imported `Lean`).
    public func size(_ args: [String]) throws(CairnError) {
        let a = try Arguments(args, options: ["--product", "--limit"], usage: "usage: cairn size [--product P]… [--limit BYTES]")
        let project = try project()
        let products = try product(project, a)
        let limit = try a.number("--limit") ?? 5_000_000
        guard shell.has("bun") else { throw CairnError("cairn size needs bun (https://bun.sh)") }
        try buildLean(project)
        let dir = project.root.appending(path: "build/size")
        try mkdir(dir)
        for p in products {
            try shell.run(["swift", "build", "-c", "release", "--product", p,
                           "-Xlinker", "-map", "-Xlinker", dir.appending(path: "\(p).map").path], in: project.swift)
        }
        let bin = try binPath(project, release: true)
        try shell.run(["bun", project.cairn.appending(path: "tools/size/size.ts").path,
                       "--bin", bin.path, "--maps", dir.path, "--out", dir.path, "--limit", String(limit),
                       "--lib", "lib\(project.manifest.name).a", "--modules", project.manifest.libs.joined(separator: ","),
                       "--swift", project.swift.standardizedFileURL.path] + products, in: project.root)
    }

    // MARK: conformance

    /// `cairn conformance [--module M] [--product P] [--n N] [--length L] [--seed S]`: the Lean
    /// model's sequences replayed on the running app through its debug socket
    /// (docs/conformance.md). The package has a generator module, by default `<App>.Conformance`,
    /// exporting `cairn_conformance_run` over Cairn's `Conformance.run` (test/fixture's is
    /// lean/Fixture/Conformance.lean) in a library of its own. It writes
    /// build/conformance/<App>.json and build/conformance/<App>/report.md. The app's window opens
    /// while it runs; it is never activated.
    public func conformance(_ args: [String]) throws(CairnError) {
        let usage = "usage: cairn conformance [--module M] [--product P] [--n N] [--length L] [--seed S]"
        let a = try Arguments(args, options: ["--module", "--product", "--n", "--length", "--seed"], usage: usage)
        let project = try project()
        guard let app = project.appModule else { throw CairnError("cairn.toml lists no `libs`") }
        let module = a.value("--module") ?? "\(app).Conformance"
        let products = try product(project, a)
        guard products.count == 1 else { throw CairnError("conformance drives one executable; give one --product") }
        guard shell.has("bun"), shell.has("clang") else { throw CairnError("cairn conformance needs bun and clang") }
        try buildLean(project)
        let env = lakeEnv(registry())
        try shell.run(["lake", "build", module], in: project.lean, env: env)
        try shell.run(["swift", "build", "--product", products[0]], in: project.swift)
        let bin = try binPath(project, release: false)
        // The host's Core Text metrics (`cairn_text_metrics`, in CairnRender), so the model lays
        // out text exactly as the app does. The app's build leaves each library target as one
        // object beside the executable; an object's strong definition replaces the weak fallback
        // in lean/c/text_host.c, as the Makefile's -force_load of CairnMetrics does.
        let metrics = ["CairnRender", "CairnFrame"].map { bin.appending(path: "\($0).o").path }
        for m in metrics where !FileManager.default.fileExists(atPath: m) {
            throw CairnError("\(m) is missing: this SwiftPM build doesn't leave an object per library target")
        }
        let dir = project.root.appending(path: "build/conformance")
        let out = dir.appending(path: app)
        try mkdir(out)
        try claims(["--out", out.appending(path: "claims.json").path])

        let prefix = try shell.capture(["lake", "env", "lean", "--print-prefix"], in: project.lean, env: env).text
        let objects = try shell.capture(["lake", "query", "+Conformance.Gen:c.o", "+\(module):c.o"], in: project.lean, env: env).text
            .split(separator: "\n").suffix(2).map(String.init)
        let sdk = try shell.capture(["xcrun", "--show-sdk-path"], in: project.root).text
        let gen = out.appending(path: "gen").path
        try shell.run(["clang", "-O2", "-I\(prefix)/include", "-DCAIRN_APP_INIT=\(project.initializer(of: module))",
                       project.cairn.appending(path: "tools/conformance/gen_main.c").path] + objects
                      + metrics + [project.root.appending(path: ".cairn/lib/lib\(project.manifest.name).a").path,
                         "-L\(sdk)/usr/lib/swift", "-lc++", "-o", gen], in: project.root)
        try shell.run(["bun", project.cairn.appending(path: "tools/conformance/driver.ts").path,
                       "--app", app, "--n", a.value("--n") ?? "1000", "--length", a.value("--length") ?? "12",
                       "--seed", a.value("--seed") ?? "1", "--bin", bin.appending(path: products[0]).path, "--gen", gen,
                       "--claims", out.appending(path: "claims.json").path, "--out", dir.path], in: project.root)
    }
}
