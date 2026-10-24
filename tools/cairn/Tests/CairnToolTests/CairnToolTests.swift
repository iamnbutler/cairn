import Foundation
import Testing
@testable import CairnTool

@Suite struct ManifestTests {
    @Test func parsesAndRendersAgain() throws {
        let text = """
            # Yap's manifest
            [package]
            name = "yap"
            version = "0.1.0-rc.2"
            description = "Dictation: \\"hold\\" and talk"
            license = "MIT"
            libs = ["Yap", "YapAbi"]  # both linked

            [dependencies]
            cairn = "^0.1.0"
            """
        let m = try Manifest.parse(text)
        #expect(m.name == "yap")
        #expect(m.version == "0.1.0-rc.2")
        #expect(m.description == "Dictation: \"hold\" and talk")
        #expect(m.libs == ["Yap", "YapAbi"])
        #expect(m.lean == "lean" && m.swift == "." && m.claims == "claims.lock")
        #expect(m.dependencies.map(\.name) == ["cairn"])
        #expect(try Manifest.parse(m.render()) == m)
    }

    @Test(arguments: [
        ("[package]\nname = \"a\"\nversion = \"0.1.0\"\nedition = \"2\"\n", "unknown key `edition`"),
        ("[package]\nname = \"a\"\nversion = \"0.1.0\"\n[registry]\n", "unknown table [registry]"),
        ("[package]\nname = \"Yap\"\nversion = \"0.1.0\"\n", "isn't a package name"),
        ("[package]\nname = \"a\"\nversion = \"0.1.0+build\"\n", "isn't a version"),
        ("[package]\nname = \"a\"\nversion = \"0.1.0\"\n[dependencies]\ncairn = \"latest\"\n", "isn't a version range"),
        ("[package]\nname = \"a\"\nname = \"b\"\n", "appears twice"),
        ("[package]\nname = 'a'\n", "values are"),
        ("name = \"a\"\n", "before any [table]"),
    ])
    func refuses(_ text: String, _ message: String) {
        #expect {
            _ = try Manifest.parse(text)
        } throws: { error in
            (error as? CairnError)?.description.contains(message) == true
        }
    }

    /// `kind`, as Cargo has it: a manifest from before kinds is a lib, and render writes it.
    @Test func kindIsLibOrBin() throws {
        let old = try Manifest.parse("[package]\nname = \"a\"\nversion = \"0.1.0\"\n")
        #expect(old.kind == .lib)
        #expect(old.render().contains("version = \"0.1.0\"\nkind = \"lib\"\n"))
        let app = try Manifest.parse("[package]\nname = \"yap\"\nversion = \"0.1.0\"\nkind = \"bin\"\n")
        #expect(app.kind == .bin)
        #expect(try Manifest.parse(app.render()) == app)
        #expect(app != old)
        #expect {
            _ = try Manifest.parse("[package]\nname = \"a\"\nversion = \"0.1.0\"\nkind = \"app\"\n")
        } throws: { error in
            (error as? CairnError)?.description == "cairn.toml: `kind` is \"lib\" or \"bin\", not \"app\""
        }
    }

    @Test func requireAddsOrUpdates() {
        var m = Manifest(name: "yap", version: "0.1.0")
        m.require("cairn", "^0.1.0")
        m.require("other", "^1.0.0")
        m.require("cairn", "^0.2.0")
        #expect(m.dependencies.map { "\($0.name) \($0.range)" } == ["cairn ^0.2.0", "other ^1.0.0"])
    }
}

@Suite struct LakefileTests {
    @Test func leanNameScopeAndRequire() {
        var lake = Lakefile(format: .lean, text: """
            import Lake
            open Lake DSL

            package yap where
              leanOptions := #[⟨`weak.cairn.claims.scope, "yap"⟩]

            require cairn from git "https://github.com/iamnbutler/cairn" @ "v0.1.0" / "lean"

            lean_lib Yap
            """)
        #expect(lake.name == "yap")
        #expect(lake.scope == "yap")
        lake.require("cairn", owner: "iamnbutler", range: "^0.1.0")
        #expect(lake.text.contains("require \"iamnbutler\" / \"cairn\" @ \"^0.1.0\"\n"))
        #expect(!lake.text.contains("from git"))
        lake.require("extra", owner: "iamnbutler", range: "^1.0.0")
        #expect(lake.text.contains("@ \"^0.1.0\"\nrequire \"iamnbutler\" / \"extra\" @ \"^1.0.0\"\n"))
    }

    @Test func leanRequireAfterPackageBlock() {
        var lake = Lakefile(format: .lean, text: "import Lake\nopen Lake DSL\n\npackage «my_app» where\n  version := v!\"0.1.0\"\n\nlean_lib MyApp\n")
        #expect(lake.name == "my_app")
        #expect(lake.scope == nil)
        lake.require("cairn", owner: "o", range: "^0.1.0")
        #expect(lake.text == "import Lake\nopen Lake DSL\n\npackage «my_app» where\n  version := v!\"0.1.0\"\n\nrequire \"o\" / \"cairn\" @ \"^0.1.0\"\n\nlean_lib MyApp\n")
    }

    @Test func tomlRequire() {
        var lake = Lakefile(format: .toml, text: """
            name = "hello"
            defaultTargets = ["Hello"]

            [[require]]
            name = "cairn"
            scope = "old"
            version = "^0.1.0"

            [[lean_lib]]
            name = "Hello"
            """)
        #expect(lake.name == "hello")
        lake.require("cairn", owner: "carl", range: "^0.2.0")
        #expect(lake.text.contains("[[require]]\nname = \"cairn\"\nscope = \"carl\"\nversion = \"^0.2.0\"\n\n[[lean_lib]]"))
        lake.require("yap", owner: "carl", range: "^0.1.0")
        #expect(lake.text.hasSuffix("\n[[require]]\nname = \"yap\"\nscope = \"carl\"\nversion = \"^0.1.0\"\n"))
    }
}

@Suite struct PublishTests {
    @Test func framesLittleEndianSections() {
        let body = Publish.frame([Data([1, 2, 3]), Data(), Data([9])])
        #expect(Array(body) == [3, 0, 0, 0, 1, 2, 3, 0, 0, 0, 0, 1, 0, 0, 0, 9])
    }

    /// Five sections, and the last, docs, empty: the registry builds docs from source and
    /// refuses a publish that carries any (nextpm#23).
    @Test func bodySendsNoDocs() throws {
        let metadata = Publish.Metadata(
            name: "hello", version: "1.0.0", kind: "lib", revision: String(repeating: "a", count: 40), toolchain: "leanprover/lean4:v4.35.0",
            description: nil, license: nil, lean: "lean", libs: ["Hello"], dependencies: [:], readme: nil)
        let body = Array(try Publish.body(metadata: metadata, pack: Data([1]), index: Data([2, 2]), claims: Data([3, 3, 3])))
        var sections: [[UInt8]] = []
        var at = 0
        while at < body.count {
            let size = body[at..<at + 4].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            sections.append(Array(body[at + 4..<at + 4 + size]))
            at += 4 + size
        }
        #expect(sections.count == 5)
        #expect(sections[1...3] == [[1], [2, 2], [3, 3, 3]])
        #expect(sections[4].isEmpty)
    }

    /// The metadata says the package's kind, so the registry can refuse a dependency on an app.
    @Test func metadataSendsKind() throws {
        let metadata = Publish.Metadata(
            name: "yap", version: "0.1.0", kind: "bin", revision: String(repeating: "a", count: 40), toolchain: "t",
            description: nil, license: nil, lean: "lean", libs: ["Yap"], dependencies: ["cairn": "^0.1.0"], readme: nil)
        let body = try Publish.body(metadata: metadata, pack: Data(), index: Data(), claims: Data())
        let size = Int(body[0]) | Int(body[1]) << 8 | Int(body[2]) << 16 | Int(body[3]) << 24
        let json = String(decoding: body[4..<4 + size], as: UTF8.self)
        #expect(json.contains("\"kind\":\"bin\""))
    }

    @Test func artifactsFromOutputs() {
        let outputs = "\"2026-03-17\"\n[\"55b6cf8474f10fe7\",\"7526447641c97ec1.ltar\"]\n"
        #expect(Publish.artifacts(outputs) == ["55b6cf8474f10fe7", "7526447641c97ec1"])
    }

    @Test func platform() {
        #expect(Publish.platform("Lean (version 4.35.0, arm64-apple-darwin24.6.0, commit abc, Release)") == "arm64-apple-darwin24.6.0")
    }


    @Test(arguments: [("0.1.0", true), ("0.1.0-rc.1", true), ("01.0.0", false), ("0.1", false), ("0.1.0+b", false)])
    func versions(_ text: String, _ ok: Bool) {
        #expect(Names.version(text) == ok)
    }
}

/// `cairn new` asks whether the package is a library or an app, unless a flag says.
@Suite struct NewTests {
    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cairn-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func manifest(_ dir: URL, _ name: String) throws -> Manifest {
        try Manifest.parse(String(contentsOf: dir.appending(path: "\(name)/cairn.toml"), encoding: .utf8))
    }

    @Test func flagsSayWhich() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        var commands = Commands()
        commands.cwd = dir
        commands.ask = { _ in Issue.record("asked with a flag"); return nil }
        try commands.new(["kit", "--lib"])
        try commands.new(["tool", "--bin"])
        #expect(try manifest(dir, "kit").kind == .lib)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "kit/Package.swift").path))
        #expect(try manifest(dir, "tool").kind == .bin)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "tool/Package.swift").path))
        #expect(throws: CairnError.self) { try commands.new(["both", "--lib", "--bin"]) }
    }

    @Test func asksUntilItKnows() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        var answers = ["maybe", "app"]
        var commands = Commands()
        commands.cwd = dir
        commands.ask = { _ in answers.isEmpty ? nil : answers.removeFirst() }
        try commands.new(["yap"])
        #expect(try manifest(dir, "yap").kind == .bin)
        #expect(answers.isEmpty)
        commands.ask = { _ in nil }
        #expect {
            try commands.new(["quiet"])
        } throws: { error in
            (error as? CairnError)?.description.contains("--lib") == true
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "quiet").path))
    }
}

/// A stand-in for the public registry: answers by path and records each request.
final class FakeRegistry: @unchecked Sendable {
    struct Seen { var method: String; var path: String; var authorization: String? }
    let lock = NSLock()
    var seen: [Seen] = []
    var answers: [String: (Int, String)]

    init(_ answers: [String: (Int, String)]) { self.answers = answers }

    var transport: Registry.Transport {
        { [self] request in
            let url = request.url!
            let path = url.path(percentEncoded: false) + (url.query.map { "?\($0)" } ?? "")
            let (status, body) = lock.withLock {
                seen.append(Seen(method: request.httpMethod ?? "GET", path: path, authorization: request.value(forHTTPHeaderField: "authorization")))
                return answers["\(request.httpMethod ?? "GET") \(path)"] ?? (404, #"{"error":{"status":404,"message":"Not found"}}"#)
            }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func registry(token: String? = nil) -> Registry {
        Registry(url: URL(string: "https://reg.test")!, token: token, transport: transport)
    }

    var requests: [Seen] { lock.withLock { seen } }
}

/// One public registry that anyone reads; only writes carry the token.
@Suite struct RegistryTests {
    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cairn-reg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func publicByDefaultAndReservoirHasNoCredential() {
        let r = Registry.current([:], saved: URL(filePath: "/nonexistent/credentials"))
        #expect(r.url.absoluteString == "https://cairn.registry.nexthub.sh")
        #expect(r.token == nil)
        #expect(r.reservoir == "https://cairn.registry.nexthub.sh/api/v1")
        #expect(r.git("carl", "hello") == "https://cairn.registry.nexthub.sh/git/carl/hello.git")
        let local = Registry.current(["CAIRN_REGISTRY": "http://cairn.registry.nexthub.localhost:9876"], saved: URL(filePath: "/nonexistent"))
        #expect(local.reservoir == "http://cairn.registry.nexthub.localhost:9876/api/v1")
        #expect(Registry(url: local.url, token: "nx_t").reservoir == local.reservoir)
    }

    /// A saved token goes only to the registry it was saved for; CAIRN_TOKEN overrides it.
    @Test func savedTokenStaysWithItsRegistry() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "credentials")
        try Registry(token: "nx_saved").save(to: file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect(Registry.current([:], saved: file).token == "nx_saved")
        #expect(Registry.current(["CAIRN_REGISTRY": "https://cairn.registry.nexthub.sh/"], saved: file).token == "nx_saved")
        #expect(Registry.current(["CAIRN_REGISTRY": "https://other.test"], saved: file).token == nil)
        #expect(Registry.current(["CAIRN_TOKEN": "nx_ci"], saved: file).token == "nx_ci")
    }

    @Test func readsSendNoTokenAndWritesNeedOne() async throws {
        let fake = FakeRegistry([
            "GET /config.json": (200, #"{"kind":"cairn","api":"https://reg.test/api/v1","git":"https://reg.test/git","registry":"r1"}"#),
            "GET /-/whoami": (200, #"{"username":"carl"}"#),
        ])
        let reader = fake.registry(token: "nx_t")
        #expect(try await reader.config().kind == "cairn")
        #expect(try await reader.whoami() == "carl")
        #expect(fake.requests.map(\.authorization) == [nil, "Bearer nx_t"])
        await #expect {
            try await fake.registry().send("PUT", "api/v1/packages/carl/hello/versions/1.0.0", write: true)
        } throws: { error in
            (error as? CairnError)?.description.contains("cairn login") == true
        }
        #expect(fake.requests.count == 2)
    }

    /// A Reservoir answer, which the registry passes through for a name it lacks, has no `yanked`.
    @Test func versionsFromReservoir() async throws {
        let fake = FakeRegistry([
            "GET /api/v1/packages/leanprover-community/batteries/versions?yanked=true": (200, #"{"schemaVersion":"1.2.0","data":[{"version":"0.0.0","revision":"130eb02e","tag":null}]}"#),
        ])
        let versions = try await fake.registry().versions("leanprover-community", "batteries")
        #expect(versions.map(\.version) == ["0.0.0"] && versions.allSatisfy { !$0.yanked })
    }

    @Test func ownerOfANameIsItsExactSearchMatch() async throws {
        let fake = FakeRegistry([
            "GET /api/v1/packages?q=hello&per_page=100": (200, #"{"data":{"items":[{"name":"hello_world","fullName":"zed/hello_world"},{"name":"hello","fullName":"carl/hello"}],"total":2}}"#),
            "GET /api/v1/packages?q=nope&per_page=100": (200, #"{"data":{"items":[],"total":0}}"#),
        ])
        #expect(try await fake.registry().owner(of: "hello") == "carl")
        #expect(try await fake.registry().owner(of: "nope") == nil)
    }

    /// `cairn add` and `cairn publish` against the stand-in, in a package `cairn new` made.
    func package() throws -> (URL, Commands) {
        let dir = try scratch()
        var commands = Commands()
        commands.shell.echo = false
        commands.cwd = dir
        try commands.new(["kit", "--lib"])
        commands.cwd = dir.appending(path: "kit")
        return (dir, commands)
    }

    @Test func addNeedsNoLogin() async throws {
        let (dir, base) = try package()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeRegistry([
            "GET /api/v1/packages?q=hello&per_page=100": (200, #"{"data":{"items":[{"name":"hello","fullName":"carl/hello"}],"total":1}}"#),
            "GET /api/v1/packages/carl/hello/versions?yanked=true": (200, #"{"data":[{"version":"1.3.0-rc.1","revision":"b","yanked":false},{"version":"1.2.0","revision":"a","yanked":false}]}"#),
            "GET /api/v1/packages/acme/wave/versions?yanked=true": (200, #"{"data":[{"version":"0.3.0","revision":"c","yanked":false}]}"#),
            "GET /api/v1/packages?q=nope&per_page=100": (200, #"{"data":{"items":[],"total":0}}"#),
        ])
        var commands = base
        commands.registry = { fake.registry() }
        try await commands.add(["hello"])
        try await commands.add(["acme/wave"])
        let lakefile = try String(contentsOf: commands.cwd.appending(path: "lean/lakefile.lean"), encoding: .utf8)
        #expect(lakefile.contains("require \"carl\" / \"hello\" @ \"^1.2.0\""))
        #expect(lakefile.contains("require \"acme\" / \"wave\" @ \"^0.3.0\""))
        #expect(fake.requests.allSatisfy { $0.authorization == nil })
        #expect(!fake.requests.contains { $0.path.hasPrefix("/api/v1/packages?q=wave") })
        await #expect {
            try await commands.add(["nope"])
        } throws: { error in
            (error as? CairnError)?.description == "nope isn't in https://reg.test"
        }
    }

    func tagged(_ commands: Commands) throws {
        let git = ["git", "-c", "user.name=t", "-c", "user.email=t@t.test", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false"]
        try commands.shell.run(["git", "add", "-A"], in: commands.cwd)
        try commands.shell.run(git + ["commit", "-qm", "kit"], in: commands.cwd)
        try commands.shell.run(git + ["tag", "v0.1.0"], in: commands.cwd)
    }

    /// The owner is --owner, else the token's login; a publish with no token stops first.
    @Test func publishOwnerIsTheTokensLoginOrTheFlag() async throws {
        let (dir, base) = try package()
        defer { try? FileManager.default.removeItem(at: dir) }
        try tagged(base)
        let fake = FakeRegistry(["GET /-/whoami": (200, #"{"username":"carl"}"#)])
        var commands = base
        commands.registry = { fake.registry() }
        await #expect {
            try await commands.publish(["--dry-run"])
        } throws: { error in
            (error as? CairnError)?.description.contains("`cairn login`") == true
        }
        #expect(fake.requests.isEmpty)

        commands.registry = { fake.registry(token: "nx_t") }
        try await commands.publish(["--dry-run"])
        #expect(fake.requests.map { "\($0.method) \($0.path) \($0.authorization ?? "-")" } == [
            "GET /-/whoami Bearer nx_t",
            "GET /api/v1/packages/carl/kit/versions?yanked=true -",
        ])

        let flagged = FakeRegistry([:])
        commands.registry = { flagged.registry(token: "nx_t") }
        try await commands.publish(["--owner", "acme", "--dry-run"])
        #expect(flagged.requests.map(\.path) == ["/api/v1/packages/acme/kit/versions?yanked=true"])
        await #expect(throws: CairnError.self) { try await commands.publish(["--owner"]) }
    }
}
