import Foundation

/// A package on disk: its root (the directory with cairn.toml) and its manifest.
public struct Project: Sendable {
    public var root: URL
    public var manifest: Manifest
    public var lean: URL { root.appending(path: manifest.lean) }
    public var swift: URL { root.appending(path: manifest.swift) }

    /// The nearest cairn.toml at or above `dir`.
    public static func find(from dir: URL) throws(CairnError) -> Project {
        var at = dir.standardizedFileURL
        while true {
            let file = at.appending(path: "cairn.toml")
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                return Project(root: at, manifest: try Manifest.parse(text))
            }
            let up = at.deletingLastPathComponent()
            if up.path == at.path { throw CairnError("no cairn.toml here or above; `cairn new <name>` starts a package") }
            at = up
        }
    }

    public func save() throws(CairnError) {
        do { try manifest.render().write(to: root.appending(path: "cairn.toml"), atomically: true, encoding: .utf8) } catch {
            throw CairnError("couldn't write cairn.toml: \(error.localizedDescription)")
        }
    }

    /// Cairn itself, or the Cairn package Lake fetched into the app's lean/.lake/packages/.
    public var cairn: URL { manifest.name == "cairn" ? root : lean.appending(path: ".lake/packages/cairn") }

    /// Check that the three names agree: cairn.toml's, the Lake package's, and the claim scope.
    public func agree() throws(CairnError) {
        let (lakefile, url) = try Lakefile.load(lean)
        guard let name = lakefile.name else { throw CairnError("\(url.lastPathComponent) has no package name") }
        guard name == manifest.name else {
            throw CairnError("cairn.toml names the package `\(manifest.name)` but \(url.lastPathComponent) names it `\(name)`; they must agree")
        }
        if let scope = lakefile.scope, scope != manifest.name {
            throw CairnError("the claim scope (cairn.claims.scope) is `\(scope)`, not the package's name `\(manifest.name)`")
        }
    }
}

/// The commands. Each takes its arguments after the command name.
public struct Commands {
    public var shell = Shell()
    public var cwd = URL(filePath: FileManager.default.currentDirectoryPath)
    /// Ask the person a question and read the answer, or `nil` at the end of input.
    public var ask: (String) -> String? = { question in
        FileHandle.standardError.write(Data(question.utf8))
        return readLine(strippingNewline: true)
    }
    public init() {}

    func project() throws(CairnError) -> Project { try Project.find(from: cwd) }

    /// The registry: CAIRN_REGISTRY or the public one, with a token only for writes.
    public var registry: () -> Registry = { Registry.current() }

    /// The environment Lake runs in: the artifact cache on, and the registry as Reservoir, which
    /// Lake reads with no credential.
    func lakeEnv(_ registry: Registry) -> [String: String] {
        ["LAKE_ARTIFACT_CACHE": "true", "RESERVOIR_API_URL": registry.reservoir]
    }

    // MARK: new

    /// `cairn new <name> [--lib | --bin]`: a package with a Lake package in lean/ that requires
    /// Cairn, a claims.lock, and for an app (`bin`) a SwiftPM executable that links it. With
    /// neither flag it asks which, as `kind` in cairn.toml says.
    public func new(_ args: [String]) throws(CairnError) {
        guard let name = args.first, !name.hasPrefix("-") else { throw CairnError("usage: cairn new <name> [--lib | --bin]") }
        guard Names.valid(name) else { throw CairnError("`\(name)` isn't a package name: lowercase letters, digits and _, starting with a letter") }
        guard !(args.contains("--lib") && args.contains("--bin")) else { throw CairnError("a package is a --lib or a --bin, not both") }
        let dir = cwd.appending(path: name)
        guard !FileManager.default.fileExists(atPath: dir.path) else { throw CairnError("\(name)/ already exists") }
        let kind: Kind = try args.contains("--lib") ? .lib : args.contains("--bin") ? .bin : askKind(name)
        let lib = kind == .lib
        let module = name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        var manifest = Manifest(name: name, version: "0.1.0")
        manifest.kind = kind
        manifest.libs = [module]
        manifest.license = "MIT"
        manifest.dependencies = [("cairn", "^0.1.0")]
        let toolchain = (try? String(contentsOf: Project(root: cwd, manifest: manifest).cairn.appending(path: "lean/lean-toolchain"), encoding: .utf8))
            ?? "leanprover/lean4:v4.35.0\n"
        var files: [(String, String)] = [
            ("cairn.toml", manifest.render()),
            ("claims.lock", "# id\tkind\tstatus\tstatement\ttitle\n"),
            (".gitignore", ".lake/\n.build/\n.cairn/\nbuild/\n"),
            ("lean/lean-toolchain", toolchain),
            ("lean/lakefile.lean", """
                import Lake
                open Lake DSL

                package \(name) where
                  leanOptions := #[⟨`weak.cairn.claims.scope, "\(name)"⟩]

                require "owner" / "cairn" @ "^0.1.0"

                @[default_target]
                lean_lib \(module) where
                  defaultFacets := #[LeanLib.staticFacet]

                """),
            ("lean/\(module).lean", """
                /-! \(module): a Cairn \(lib ? "library" : "app"). Its claims are `\(name)^N`. -/
                import Cairn

                namespace \(module)

                end \(module)

                """),
        ]
        if !lib {
            files.append(("Package.swift", """
                // swift-tools-version: 6.0
                // The app's host: Cairn's AppKit host, linking .cairn/lib/lib\(name).a, which
                // `cairn build` makes from the Lean code (bin/cairn-link).
                import PackageDescription

                let lib = Context.packageDirectory + "/.cairn/lib"

                let package = Package(
                    name: "\(name)",
                    platforms: [.macOS(.v14)],
                    dependencies: [.package(url: "CAIRN_GIT_URL", from: "0.1.0")],
                    targets: [
                        .executableTarget(
                            name: "\(module)",
                            dependencies: [.product(name: "CairnHost", package: "cairn")],
                            linkerSettings: [.unsafeFlags(["-L" + lib, "-l\(name)"])]),
                    ]
                )

                """))
            files.append(("Sources/\(module)/main.swift", "import CairnHost\n\n// Start the host with this app's Lean code; see Cairn's docs/package.md.\n"))
        }
        if !lib { manifest.libs = [module] }
        do {
            for (path, text) in files {
                let url = dir.appending(path: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch { throw CairnError("couldn't write \(name)/: \(error.localizedDescription)") }
        _ = try? shell.capture(["git", "init", "-q"], in: dir, check: false)
        print("Created \(name)/. Next: `cd \(name) && cairn add cairn`, which points the lakefile at the registry, then `cairn build`.")
    }

    /// Ask whether a new package is a library or an app, until the answer is one of them.
    func askKind(_ name: String) throws(CairnError) -> Kind {
        while true {
            guard let answer = ask("Is \(name) a library other packages depend on (lib), or an app (bin)? [lib/bin] ") else {
                throw CairnError("say which: `cairn new \(name) --lib` or `cairn new \(name) --bin`")
            }
            switch answer.trimmingCharacters(in: .whitespaces).lowercased() {
            case "lib", "library", "l": return .lib
            case "bin", "app", "b", "a": return .bin
            default: continue
            }
        }
    }

    // MARK: add

    /// `cairn add [<owner>/]<name>[@<range>]`: record the dependency in cairn.toml and require it
    /// in the lakefile from the registry. Package.swift is the author's to edit; this prints its
    /// line. It needs no login. Lake asks for `<owner>/<name>`, so with no owner it looks the
    /// name up: a name has one owner in the registry.
    public func add(_ args: [String]) async throws(CairnError) {
        guard let spec = args.first else { throw CairnError("usage: cairn add [<owner>/]<name>[@<range>]") }
        let parts = spec.split(separator: "@", maxSplits: 1).map(String.init)
        let path = parts[0].split(separator: "/", maxSplits: 1).map(String.init)
        let dep = path.last ?? ""
        guard Names.valid(dep) else { throw CairnError("`\(dep)` isn't a package name") }
        let registry = self.registry()
        let found: String?
        if path.count == 2 { found = path[0] } else { found = try await registry.owner(of: dep) }
        guard let owner = found, !owner.isEmpty else { throw CairnError("\(dep) isn't in \(registry.url.absoluteString)") }
        var range = parts.count > 1 ? parts[1] : ""
        if range.isEmpty {
            let versions = try await registry.versions(owner, dep)
            guard let latest = versions.first(where: { !$0.yanked && !$0.version.contains("-") }) ?? versions.first(where: { !$0.yanked }) else {
                throw CairnError("\(dep) isn't in \(registry.url.absoluteString)")
            }
            range = "^" + latest.version
        }
        guard Names.range(range) else { throw CairnError("`\(range)` isn't a version range like ^0.1.0") }
        var project = try project()
        project.manifest.require(dep, range)
        var (lakefile, url) = try Lakefile.load(project.lean)
        lakefile.require(dep, owner: owner, range: range)
        do { try lakefile.text.write(to: url, atomically: true, encoding: .utf8) } catch { throw CairnError("couldn't write \(url.path)") }
        try project.save()
        let from = range.replacing(/^(\^|~|=|>=)/, with: "").replacing(/-.*$/, with: "")
        print("Added \(dep) \(range) to cairn.toml and \(url.lastPathComponent).")
        print("For its Swift products, Package.swift needs:\n    .package(url: \"\(registry.git(owner, dep))\", from: \"\(from)\")")
    }

    // MARK: build

    /// `cairn build [--release]`: `lake cache get`, `lake build`, `cairn-link`, `swift build`.
    public func build(_ args: [String]) throws(CairnError) {
        let project = try project()
        try project.agree()
        let env = lakeEnv(registry())
        guard shell.has("lake") else { throw CairnError("lake isn't on PATH; install elan (AGENTS.md, Toolchain)") }
        // Prebuilt Lean for every dependency (and this package, for a published commit). A miss
        // only means building locally, so it never fails the build.
        if (try? shell.capture(["lake", "cache", "get"], in: project.lean, env: env, check: false))?.status != 0 {
            FileHandle.standardError.write(Data("cairn: the build cache had nothing; building locally\n".utf8))
        }
        try shell.run(["lake", "build"], in: project.lean, env: env)
        let package = project.swift.appending(path: "Package.swift")
        guard FileManager.default.fileExists(atPath: package.path) else { return }
        // No Lean libraries of its own (Cairn itself): nothing to link; Cairn's `make lean`
        // writes its own build/lib/libcairn_lean.a, and a second copy here would only drift.
        if project.manifest.libs.isEmpty {
            try shell.run(["swift", "build"] + (args.contains("--release") ? ["-c", "release"] : []), in: project.swift)
            return
        }
        let link = project.cairn.appending(path: "bin/cairn-link")
        guard FileManager.default.isExecutableFile(atPath: link.path) else {
            throw CairnError("\(link.path) is missing: Cairn 0.1.0 or later ships it (docs/package.md)")
        }
        let out = project.root.appending(path: ".cairn/lib/lib\(project.manifest.name).a")
        try shell.run([link.path] + project.manifest.libs.flatMap { ["--lib", $0] } + ["--out", out.path], in: project.lean, env: env)
        try shell.run(["swift", "build"] + (args.contains("--release") ? ["-c", "release"] : []), in: project.swift)
    }

    // MARK: doc

    /// `cairn doc [--private] [--open]`: the package's docs in build/doc/<name>/, as Cairn's
    /// `make doc` makes them (docs/doc.md), with each dependency linked to its docs on the site.
    public func doc(_ args: [String]) throws(CairnError) {
        let project = try project()
        let name = project.manifest.name
        let dir = project.root.appending(path: "build/doc/\(name)")
        // With the artifact cache on, Lake keeps .olean files in the cache, not in the build
        // directory, and the doc and claims tools import modules from the build directory.
        var env = lakeEnv(registry())
        env["LAKE_ARTIFACT_CACHE"] = "false"
        let modules = name == "cairn"
            ? ["Cairn", "Cairn.Claims", "Cairn.Fuzz", "Cairn.Fuzz.Trusted.Claims", "Cairn.Fuzz.Trusted.Export"]
            : project.manifest.libs
        guard !modules.isEmpty else { throw CairnError("cairn.toml lists no `libs` to document") }
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { throw CairnError("couldn't create \(dir.path)") }
        try shell.run(["lake", "build"], in: project.lean, env: env)
        let docJson = try shell.capture(["lake", "exe", "doc", "--check"] + modules, in: project.lean, env: env)
        let claimsJson = try shell.capture(["lake", "exe", "claims"] + modules, in: project.lean, env: env)
        do {
            try docJson.stdout.write(to: dir.appending(path: "doc.json"))
            try claimsJson.stdout.write(to: dir.appending(path: "claims.json"))
        } catch { throw CairnError("couldn't write \(dir.path)") }
        var links: [String] = []
        for dep in project.manifest.dependencies {
            // Lake checks each dependency out at its tag, beside its own cairn.toml.
            let checkout = project.lean.appending(path: ".lake/packages/\(dep.name)")
            guard let text = try? String(contentsOf: checkout.appending(path: "cairn.toml"), encoding: .utf8),
                  let theirs = try? Manifest.parse(text) else { continue }
            let libs = dep.name == "cairn" ? ["Cairn"] : theirs.libs
            for lib in libs { links += ["--link", "\(lib).=/docs/\(dep.name)/\(theirs.version)/"] }
        }
        let script = project.cairn.appending(path: "tools/doc/cairn-doc.ts")
        guard shell.has("bun") else { throw CairnError("cairn doc needs bun (https://bun.sh)") }
        try shell.run(["bun", script.path, "--name", name, "--dir", dir.path, "--root", project.root.path] + links
            + args.filter { $0 == "--private" || $0 == "--open" }, in: project.root)
    }

    // MARK: publish

    /// `cairn publish [--owner <login>] [--dry-run]`: send the version at tag v<version> to the
    /// registry: its git objects and claims.lock, then its build outputs for Lake's cache. It
    /// sends no docs: the registry will build them from the source (docs/cli.md). It publishes
    /// under `--owner`, else under the login the token belongs to (`GET /-/whoami`).
    public func publish(_ args: [String]) async throws(CairnError) {
        let project = try project()
        try project.agree()
        let m = project.manifest
        let dry = args.contains("--dry-run")
        var flagged: String?
        if let at = args.firstIndex(of: "--owner") {
            guard args.indices.contains(at + 1), !args[at + 1].hasPrefix("-") else { throw CairnError("usage: cairn publish [--owner <login>] [--dry-run]") }
            flagged = args[at + 1]
        }
        let registry = self.registry()
        guard registry.token != nil else {
            throw CairnError("publishing needs a token: `cairn login` with a nexthub token that has package:write, or set CAIRN_TOKEN")
        }
        let root = project.root
        let tag = "v\(m.version)"
        guard let revision = try? shell.capture(["git", "rev-parse", "--verify", "\(tag)^{commit}"], in: root).text else {
            throw CairnError("there's no tag \(tag); tag the commit to publish (`git tag \(tag)`)")
        }
        let head = try shell.capture(["git", "rev-parse", "HEAD"], in: root).text
        guard head == revision else { throw CairnError("\(tag) is \(revision.prefix(10)), but HEAD is \(head.prefix(10)); check out \(tag) to publish it") }
        let dirty = try shell.capture(["git", "status", "--porcelain", "--untracked-files=no"], in: root).text
        guard dirty.isEmpty else { throw CairnError("the working tree has uncommitted changes; publish exactly what \(tag) holds") }

        let owner: String
        if let flagged { owner = flagged } else { owner = try await registry.whoami() }
        let published = try await registry.versions(owner, m.name)
        guard !published.contains(where: { $0.version == m.version }) else { throw CairnError("\(m.name) \(m.version) is already published") }

        // The objects new since the published versions this clone has; the registry serves every
        // pack, so a clone gets the whole history.
        var input = revision + "\n"
        for old in published where (try? shell.capture(["git", "cat-file", "-e", "\(old.revision)^{commit}"], in: root, check: false))?.status == 0 {
            input += "^\(old.revision)\n"
        }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "cairn-publish-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        do { try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true) } catch { throw CairnError("couldn't create \(scratch.path)") }
        let base = scratch.appending(path: "pack").path
        let sha = try shell.capture(["git", "pack-objects", "--revs", "-q", base], in: root, input: Data(input.utf8)).text
        func read(_ url: URL) throws(CairnError) -> Data {
            do { return try Data(contentsOf: url) } catch { throw CairnError("couldn't read \(url.path)") }
        }
        let pack = try read(URL(filePath: "\(base)-\(sha).pack"))
        let index = try read(URL(filePath: "\(base)-\(sha).idx"))

        let toolchain = (try? String(contentsOf: project.lean.appending(path: "lean-toolchain"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let readme = (try? String(contentsOf: root.appending(path: "README.md"), encoding: .utf8)).map { String($0.prefix(512 * 1024)) }
        // From the tag, not the disk: an untracked Package.swift isn't published.
        let swift = !((try? shell.capture(["git", "ls-tree", "--name-only", revision, "--", Publish.swiftManifest(m.swift)], in: root).text) ?? "").isEmpty
        let metadata = Publish.Metadata(
            name: m.name, version: m.version, kind: m.kind.rawValue, revision: revision, toolchain: toolchain, description: m.description,
            license: m.license, lean: m.lean, swift: swift, libs: m.libs, dependencies: Dictionary(m.dependencies.map { ($0.name, $0.range) }) { $1 },
            readme: readme)
        let claims = (try? Data(contentsOf: root.appending(path: m.claims))) ?? Data()
        let body = try Publish.body(metadata: metadata, pack: pack, index: index, claims: claims)
        let size = ByteCountFormatter.string(fromByteCount: Int64(body.count), countStyle: .file)
        if dry {
            print("Would publish \(owner)/\(m.name) \(m.version) at \(revision.prefix(10)) to \(registry.url.absoluteString): \(size).")
            return
        }
        try await registry.send("PUT", "api/v1/packages/\(owner)/\(m.name)/versions/\(m.version)", body: body, type: "application/octet-stream", write: true)
        print("Published \(owner)/\(m.name) \(m.version) (\(size)).")
        try await outputs(project, registry, owner, revision, toolchain)
    }

    /// Upload the build's artifacts and its outputs map, so `lake cache get` finds this version
    /// prebuilt. Lake's own `cache put` speaks only to S3, so `cairn` does it.
    func outputs(_ project: Project, _ registry: Registry, _ owner: String, _ revision: String, _ toolchain: String) async throws(CairnError) {
        let env = lakeEnv(registry)
        let map = FileManager.default.temporaryDirectory.appending(path: "cairn-outputs-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: map) }
        try shell.run(["lake", "build", "-o", map.path], in: project.lean, env: env)
        let cache = try shell.capture(["lake", "env", "printenv", "LAKE_CACHE_DIR"], in: project.lean, env: env).text
        let lean = try shell.capture(["lake", "env", "lean", "--version"], in: project.lean, env: env).text
        guard let platform = Publish.platform(lean) else { throw CairnError("couldn't read the platform from `\(lean)`") }
        let text: String
        do { text = try String(contentsOf: map, encoding: .utf8) } catch { throw CairnError("lake wrote no outputs map") }
        let wanted = Publish.artifacts(text)
        let dir = URL(filePath: cache).appending(path: "artifacts")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var sent = 0
        for file in files {
            let hash = String(file.prefix { $0 != "." })
            guard wanted.contains(hash), let data = try? Data(contentsOf: dir.appending(path: file)) else { continue }
            try await registry.send("PUT", "api/v1/packages/\(owner)/\(project.manifest.name)/artifacts/\(hash).art", body: data, type: "application/vnd.reservoir.artifact", write: true)
            sent += 1
        }
        var query = URLComponents()
        query.queryItems = [.init(name: "rev", value: revision), .init(name: "platform", value: platform), .init(name: "toolchain", value: toolchain)]
        try await registry.send("PUT", "api/v1/packages/\(owner)/\(project.manifest.name)/build-outputs?\(query.percentEncodedQuery ?? "")",
                                body: Data(text.utf8), type: "application/vnd.reservoir.outputs+json-lines", write: true)
        print("Uploaded \(sent) build artifacts for \(platform).")
    }

    // MARK: login

    /// `cairn login`: read a token from stdin, check it with the registry, and save it for this
    /// user. Only `cairn publish` uses it; reading the registry needs none.
    public func login(_ args: [String]) async throws(CairnError) {
        guard args.isEmpty else { throw CairnError("usage: cairn login (then paste a token); CAIRN_REGISTRY picks another registry") }
        var registry = self.registry()
        FileHandle.standardError.write(Data("Token for \(registry.url.absoluteString) (a nexthub token with package:write): ".utf8))
        guard let token = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces), !token.isEmpty else {
            throw CairnError("no token given")
        }
        registry.token = token
        _ = try await registry.config()
        let login = try await registry.whoami()
        try registry.save()
        print("Logged in to \(registry.url.absoluteString) as \(login); saved to \(Registry.file.path).")
        print("`cairn publish` publishes under \(login), or under an Org you can write to with --owner.")
    }
}
