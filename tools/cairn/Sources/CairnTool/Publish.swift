import Foundation

/// The body of `cairn publish`, as the registry reads it (nextpm's cairn kind, publish.ts):
/// five or six sections, each a little-endian u32 length and its bytes, in this order.
public enum Publish {
    public struct Metadata: Encodable, Sendable {
        public var name: String
        public var version: String
        /// `lib` or `bin`, from cairn.toml. The registry refuses a dependency on a `bin`.
        public var kind: String
        public var revision: String
        public var toolchain: String
        public var description: String?
        public var license: String?
        public var lean: String
        /// Whether the tagged commit has the package's Package.swift (cairn.toml's `swift`
        /// directory), so the registry and the site know it has a Swift side. A pure-Lean
        /// package has none.
        public var swift = false
        public var libs: [String]
        public var dependencies: [String: String]
        public var readme: String?
    }

    /// The sixth section's name in a registry's config.json (`publish.sections`): the claims
    /// export, `lake exe claims --scope <name>` (docs/claim-pages.md). A registry that doesn't
    /// list it takes five sections, so `cairn publish` sends it only to one that does.
    public static let exportSection = "claims.json"

    /// `metadata` (JSON), `pack`, `index`, `claims.lock`, `docs`, then the claims export when
    /// there is one (`exportSection`). The docs section is always empty:
    /// a registry never takes docs from a publisher, since HTML served from an upload runs as the
    /// registry's origin (nextpm#23 answers a non-empty one with 400). It will build them from
    /// the published source instead, as docs.rs does.
    public static func frame(_ sections: [Data]) -> Data {
        var out = Data()
        for section in sections {
            var size = UInt32(section.count).littleEndian
            withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
            out.append(section)
        }
        return out
    }

    public static func body(metadata: Metadata, pack: Data, index: Data, claims: Data, export: Data = Data()) throws(CairnError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json: Data
        do { json = try encoder.encode(metadata) } catch { throw CairnError("couldn't encode the metadata: \(error)") }
        return frame([json, pack, index, claims, Data()] + (export.isEmpty ? [] : [export]))
    }

    /// The artifact hashes a build-outputs map names: Lake's 16-digit content hashes. Upload
    /// only these, not the whole cache, which holds every package's artifacts.
    public static func artifacts(_ outputs: String) -> Set<String> {
        Set(outputs.matches(of: /"([0-9a-f]{16})(?:\.[a-z0-9.]+)?"/).map { String($0.1) })
    }

    /// The path of Package.swift in the repository, for cairn.toml's `swift` directory.
    public static func swiftManifest(_ swift: String) -> String {
        let dir = swift.trimmingPrefix("./").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return dir.isEmpty || dir == "." ? "Package.swift" : "\(dir)/Package.swift"
    }

    /// Lake's platform, the second field of `lean --version`:
    /// `Lean (version 4.35.0, arm64-apple-darwin24.6.0, commit …, Release)`.
    public static func platform(_ leanVersion: String) -> String? {
        leanVersion.firstMatch(of: /\(version [^,]+, ([^,]+),/).map { String($0.1) }
    }
}
