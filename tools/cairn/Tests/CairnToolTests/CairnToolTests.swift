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

    @Test func reservoirCarriesToken() {
        let r = Registry(url: URL(string: "https://x.cairn.example.dev")!, token: "nx_t")
        #expect(r.reservoir == "https://cairn:nx_t@x.cairn.example.dev/api/v1")
        #expect(r.git("carl", "hello") == "https://x.cairn.example.dev/git/carl/hello.git")
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
