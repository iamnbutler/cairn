import Foundation

/// The body of `cairn publish`, as the registry reads it (nextpm's cairn kind, publish.ts):
/// five sections, each a little-endian u32 length and its bytes, in this order.
public enum Publish {
    public struct Metadata: Encodable, Sendable {
        public var name: String
        public var version: String
        public var revision: String
        public var toolchain: String
        public var description: String?
        public var license: String?
        public var lean: String
        public var libs: [String]
        public var dependencies: [String: String]
        public var readme: String?
    }

    /// `metadata` (JSON), `pack`, `index`, `claims.lock`, `docs` (a gzipped tar, or empty for none).
    public static func frame(_ sections: [Data]) -> Data {
        var out = Data()
        for section in sections {
            var size = UInt32(section.count).littleEndian
            withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
            out.append(section)
        }
        return out
    }

    public static func body(metadata: Metadata, pack: Data, index: Data, claims: Data, docs: Data) throws(CairnError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json: Data
        do { json = try encoder.encode(metadata) } catch { throw CairnError("couldn't encode the metadata: \(error)") }
        return frame([json, pack, index, claims, docs])
    }

    /// The artifact hashes a build-outputs map names: Lake's 16-digit content hashes. Upload
    /// only these, not the whole cache, which holds every package's artifacts.
    public static func artifacts(_ outputs: String) -> Set<String> {
        Set(outputs.matches(of: /"([0-9a-f]{16})(?:\.[a-z0-9.]+)?"/).map { String($0.1) })
    }

    /// Lake's platform, the second field of `lean --version`:
    /// `Lean (version 4.35.0, arm64-apple-darwin24.6.0, commit …, Release)`.
    public static func platform(_ leanVersion: String) -> String? {
        leanVersion.firstMatch(of: /\(version [^,]+, ([^,]+),/).map { String($0.1) }
    }
}
