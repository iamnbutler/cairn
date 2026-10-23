import CairnFrame
import CairnHost
import Foundation

/// `readFile` and `writeFile` (Files) against the file system, in a scratch directory:
///
/// - `effects.write-file`: `done` only when the file then holds exactly the bytes, creating
///   missing directories; replacing is atomic (a reader running alongside sees the old bytes or
///   the new ones, never a mix or a short file); a failed write leaves the old file as it was;
///   paths that can't name a file (empty, NUL inside) are `failed invalid`.
/// - `effects.read-file`: the file's bytes exactly; a missing file is `failed notFound`, a
///   directory or an unreadable file `failed`, a bad path `failed invalid`.
final class FilesSuite: Suite {
    let name = "files"
    let crashCheck = "effects.write-file"
    let checks: [String: CheckInfo] = [
        "effects.read-file": CheckInfo(
            title: "`readFile` replies with the file's bytes, or `failed`",
            trusted: ["host/Sources/CairnHost/World.swift (Files)"],
            oracle: "the bytes written, and the file system's state (missing, directory, unreadable)"),
        "effects.write-file": CheckInfo(
            title: "`writeFile` is atomic, and replies `done` only when the bytes are there",
            trusted: ["host/Sources/CairnHost/World.swift (Files)"],
            oracle: "FileManager reads of the file, and a concurrent reader during replacement"),
    ]

    func cases(for n: Int) -> Int { max(2, n / 4) }
    func setUp() {}

    /// A path component: text from the pool that is a legal file name (sometimes not, to check
    /// the refusal).
    static func component(_ g: inout SplitMix) -> String {
        for _ in 0..<20 {
            let s = TextPool.string(&g, maxParts: 6)
            if s.isEmpty || s == "." || s == ".." || s.contains("/") || s.utf8.count > 200 { continue }
            if s.utf8.contains(0) && !g.chance(1, 4) { continue }
            return s
        }
        return "f\(g.below(1000))"
    }

    static func data(_ g: inout SplitMix) -> [UInt8] {
        g.weighted([
            (1, { _ in [] }),
            (6, { EventsSuite.bytes(&$0) }),
            (1, { g in [UInt8](repeating: UInt8(truncatingIfNeeded: g.next()), count: g.range(1 << 16, 1 << 21)) }),
        ])
    }

    /// The errno of making `root/parts…` (directories, then a file) with mkdir and open, if any.
    static func posixRefuses(_ root: String, _ parts: [String]) -> Int32? {
        var p = root
        if mkdir(p, 0o755) != 0 && errno != EEXIST { return errno }
        for (i, c) in parts.enumerated() {
            p += "/" + c
            if i == parts.count - 1 {
                let fd = open(p, O_CREAT | O_WRONLY, 0o644)
                if fd < 0 { return errno }
                close(fd)
            } else if mkdir(p, 0o755) != 0 && errno != EEXIST {
                return errno
            }
        }
        return nil
    }

    func isFailure(_ r: Reply, _ f: Fault? = nil) -> Bool {
        if case let .failed(got, _) = r { return f == nil || got == f } else { return false }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let root = NSTemporaryDirectory() + "cairn-fuzz-files-\(getpid())-\(g.next())"
        defer {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root)
            try? FileManager.default.removeItem(atPath: root)
        }
        let w = "effects.write-file", rd = "effects.read-file"
        let parts = (0..<g.range(1, 3)).map { _ in Self.component(&g) }
        let path = root + "/" + parts.joined(separator: "/")
        if path.utf8.contains(0) {
            r.expect(w, isFailure(Files.write(path, [1]), .invalid), "writeFile to a path with NUL is not `failed invalid`")
            r.expect(rd, isFailure(Files.read(path), .invalid), "readFile of a path with NUL is not `failed invalid`")
            r.count(w, "nulPaths")
            return
        }
        // Whether the file system takes these names at all (APFS refuses unassigned code points
        // and noncharacters with EILSEQ): the oracle makes the same path with POSIX calls.
        if let e = Self.posixRefuses(root + "-oracle", parts) {
            let reply = Files.write(path, [1])
            r.expect(w, isFailure(reply, .invalid), "writeFile to a name the file system refuses (errno \(e)): \(reply)")
            r.count(w, "refusedNames")
            try? FileManager.default.removeItem(atPath: root + "-oracle")
            return
        }
        try? FileManager.default.removeItem(atPath: root + "-oracle")
        r.expect(rd, isFailure(Files.read(path), .notFound), "readFile of a missing file: \(Files.read(path))")
        r.expect(w, isFailure(Files.write("", [1]), .invalid), "writeFile to the empty path")

        // Write, read back, replace: each time exactly the bytes.
        var current: [UInt8]?
        for _ in 0..<g.range(1, 4) {
            let bytes = Self.data(&g)
            let old = current
            // A reader alongside a replacement sees old or new bytes, nothing else.
            let racing = old != nil && g.chance(1, 3)
            let torn = Locked<Int>(0), seen = Locked<Int>(0)
            let stop = Locked(false), group = DispatchGroup()
            if racing, let old {
                DispatchQueue.global().async(group: group) {
                    while !stop.value {
                        if let d = FileManager.default.contents(atPath: path) {
                            let b = [UInt8](d)
                            if b != old && b != bytes { torn.update { $0 += 1 } }
                            seen.update { $0 += 1 }
                        }
                    }
                }
            }
            let reply = Files.write(path, bytes)
            stop.value = true
            group.wait()
            guard r.expect(w, reply == .done, "writeFile of \(bytes.count) bytes: \(reply)") else { return }
            r.expect(w, FileManager.default.contents(atPath: path).map { [UInt8]($0) } == bytes,
                     "after `done` the file does not hold the \(bytes.count) bytes written")
            if racing {
                r.expect(w, torn.value == 0, "a reader saw \(torn.value) torn files in \(seen.value) reads while \(old!.count) bytes were replaced by \(bytes.count)")
                r.count(w, "racedReads", seen.value)
            }
            r.expect(rd, Files.read(path) == .bytes(bytes), "readFile after writing \(bytes.count) bytes")
            r.count(w, "bytes", bytes.count)
            current = bytes
        }

        // Reading a directory, and writing where a directory or a file is in the way.
        let dir = (path as NSString).deletingLastPathComponent
        r.expect(rd, isFailure(Files.read(dir)), "readFile of a directory: \(Files.read(dir))")
        let under = path + "/x"
        r.expect(w, isFailure(Files.write(under, [1])), "writeFile under a file succeeded")
        r.expect(w, isFailure(Files.write(dir, [1])), "writeFile over a directory succeeded")
        r.expect(w, FileManager.default.contents(atPath: path).map { [UInt8]($0) } == current,
                 "a failed write changed the file")

        // Permissions: an unreadable file, and a read-only directory.
        if g.chance(1, 3), getuid() != 0 {
            chmod(path, 0o000)
            r.expect(rd, isFailure(Files.read(path), .denied), "readFile of an unreadable file: \(Files.read(path))")
            chmod(path, 0o644)
            chmod(dir, 0o555)
            let reply = Files.write(path, [9])
            r.expect(w, isFailure(reply, .denied), "writeFile in a read-only directory: \(reply)")
            chmod(dir, 0o755)
            r.expect(w, FileManager.default.contents(atPath: path).map { [UInt8]($0) } == current,
                     "a refused write changed the file")
            r.count(w, "permissions")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "Files.write and Files.read under \(NSTemporaryDirectory())"
    }
}
