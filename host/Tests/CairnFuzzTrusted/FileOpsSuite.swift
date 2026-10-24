import CairnFrame
import CairnHost
import Foundation

/// `appendFile`, `listDir`, `deleteFile` and the `watchFile` subscription, against the file
/// system in a scratch directory (nothing outside it is touched):
///
/// - `effects.append-file`: after `done` the file holds exactly the old bytes and then the new
///   ones; a new file is mode 600 under created directories; appenders on several threads each
///   land whole and in their own order; a directory, a path under a file, NUL and the empty
///   path fail and change nothing.
/// - `effects.list-dir`: exactly the names made (files, directories, links), sorted by UTF-8
///   bytes, the same bytes `readdir` gives; missing is `notFound`, a file `invalid`, an
///   unreadable directory `denied`.
/// - `effects.make-dir`: after `done` the path is a directory, each directory made is mode 700
///   (a umask doesn't widen or narrow it), one already there is `done` and left as it was; a
///   file in the way, a path under a file, NUL and the empty path fail.
/// - `effects.delete-file`: a file or a link (not its target) is gone after `done`; again is
///   `notFound`; a directory is `invalid` and stays; a read-only parent is `denied`.
/// - `subs.watch-file`: every change (write in place, atomic replace, append, delete, create,
///   touch, chmod) brings `changed` within a few polls; an untouched file brings none; after
///   the stop has been handled none at all. The host reports a change once the file has held
///   still for a poll, so an operation brings one `changed`, or one per system call that
///   changes the file when a poll fits between them (`seenTwice` counts those).
final class FileOpsSuite: Suite {
    let name = "fileops"
    let crashCheck = "effects.append-file"
    let checks: [String: CheckInfo] = [
        "effects.append-file": CheckInfo(
            title: "`appendFile` adds exactly the bytes at the end, or fails and adds nothing",
            trusted: ["host/Sources/CairnHost/FileEffects.swift (Files.append)"],
            oracle: "the concatenation of what was appended; FileManager reads; POSIX modes"),
        "effects.list-dir": CheckInfo(
            title: "`listDir` lists exactly the directory's names, sorted",
            trusted: ["host/Sources/CairnHost/FileEffects.swift (Files.list)"],
            oracle: "the names the case created, and FileManager.contentsOfDirectory"),
        "effects.make-dir": CheckInfo(
            title: "`makeDir` makes a private directory and its parents",
            trusted: ["host/Sources/CairnHost/FileEffects.swift (Files.makeDir)"],
            oracle: "stat of each component before and after"),
        "effects.delete-file": CheckInfo(
            title: "`deleteFile` removes a file or link and never a directory",
            trusted: ["host/Sources/CairnHost/FileEffects.swift (Files.delete)"],
            oracle: "lstat before and after"),
        "subs.watch-file": CheckInfo(
            title: "`watchFile` reports every change to the file, and nothing else",
            trusted: ["host/Sources/CairnHost/World.swift (watchFile)", "FileEffects.swift (FileSignature)"],
            oracle: "the changes the case made, and when"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 20) }
    func setUp() {}

    func isFailure(_ r: Reply, _ f: Fault? = nil) -> Bool {
        if case let .failed(got, _) = r { return f == nil || got == f } else { return false }
    }

    func contents(_ p: String) -> [UInt8]? { FileManager.default.contents(atPath: p).map { [UInt8]($0) } }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let root = NSTemporaryDirectory() + "cairn-fuzz-fileops-\(getpid())-\(g.next())"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer {
            if let e = FileManager.default.enumerator(atPath: root) {
                for case let p as String in e { chmod(root + "/" + p, 0o755) }
            }
            try? FileManager.default.removeItem(atPath: root)
        }
        switch g.below(5) {
        case 0: append(&g, r, root)
        case 1: list(&g, r, root)
        case 2: delete(&g, r, root)
        case 3: makeDir(&g, r, root)
        default: watch(&g, r, root)
        }
    }

    // MARK: appendFile

    func append(_ g: inout SplitMix, _ r: Recorder, _ root: String) {
        let c = "effects.append-file"
        let parts = (0..<g.range(1, 3)).map { _ in FilesSuite.component(&g) }
        let path = root + "/" + parts.joined(separator: "/")
        if path.utf8.contains(0) {
            r.expect(c, isFailure(Files.append(path, [1]), .invalid), "appendFile to a path with NUL")
            return
        }
        if FilesSuite.posixRefuses(root + "-oracle", parts) != nil {
            try? FileManager.default.removeItem(atPath: root + "-oracle")
            r.expect(c, isFailure(Files.append(path, [1]), .invalid), "appendFile to a refused name")
            r.count(c, "refusedNames")
            return
        }
        try? FileManager.default.removeItem(atPath: root + "-oracle")
        r.expect(c, isFailure(Files.append("", [1]), .invalid), "appendFile to the empty path")
        // The directories it will make, each to be mode 700 (Yap's transcript folder is).
        let made = (1..<parts.count).map { root + "/" + parts[0..<$0].joined(separator: "/") }

        var want: [UInt8] = []
        for i in 0..<g.range(1, 5) {
            let bytes = FilesSuite.data(&g)
            let reply = Files.append(path, bytes)
            guard r.expect(c, reply == .done, "appendFile of \(bytes.count) bytes: \(reply)") else { return }
            want += bytes
            r.expect(c, contents(path) == want, "after `done` the file is not the \(want.count) bytes appended")
            if i == 0 {
                var st = stat()
                stat(path, &st)
                r.expect(c, st.st_mode & 0o777 == 0o600, "a new file has mode \(String(st.st_mode & 0o777, radix: 8)), not 600")
                for d in made {
                    stat(d, &st)
                    r.expect(c, st.st_mode & 0o777 == 0o700, "a made directory has mode \(String(st.st_mode & 0o777, radix: 8)), not 700")
                }
            }
            r.count(c, "bytes", bytes.count)
        }

        // Several appenders at once: each one's bytes land whole, in its own order.
        if g.chance(1, 2) {
            let threads = g.range(2, 4)
            let chunks: [[Int]] = (0..<threads).map { _ in (0..<g.range(1, 6)).map { _ in g.elem([1, 7, 100, 4096, 70_000]) } }
            let failed = Locked(false)
            let group = DispatchGroup()
            for t in 0..<threads {
                let mine = chunks[t]
                DispatchQueue.global().async(group: group) {
                    for n in mine where Files.append(path, [UInt8](repeating: UInt8(200 + t), count: n)) != .done {
                        failed.value = true
                    }
                }
            }
            group.wait()
            r.expect(c, !failed.value, "a concurrent append failed")
            guard let all = contents(path), all.count == want.count + chunks.joined().reduce(0, +),
                  Array(all.prefix(want.count)) == want else {
                r.fail(c, "concurrent appends lost or changed bytes")
                return
            }
            // Split the new bytes into runs of one tag; each run is whole chunks of that thread.
            var queues = chunks
            var i = want.count
            while i < all.count {
                let tag = all[i]
                var j = i
                while j < all.count && all[j] == tag { j += 1 }
                guard tag >= 200, Int(tag - 200) < threads else { r.fail(c, "a stray byte \(tag)"); return }
                var left = j - i
                while left > 0, let n = queues[Int(tag - 200)].first, n <= left {
                    left -= n
                    queues[Int(tag - 200)].removeFirst()
                }
                guard left == 0 else { r.fail(c, "an append was split by another (run of \(j - i) bytes)"); return }
                i = j
            }
            r.ran(c)
            r.count(c, "concurrentAppends", chunks.joined().count)
        }

        // Where a file can't be appended: a directory, under a file.
        let dir = (path as NSString).deletingLastPathComponent
        r.expect(c, isFailure(Files.append(dir, [1]), .invalid), "appendFile to a directory: \(Files.append(dir, [1]))")
        r.expect(c, isFailure(Files.append(path + "/x", [1])), "appendFile under a file succeeded")
        let before = contents(path)
        if g.chance(1, 3), getuid() != 0 {
            chmod(path, 0o400)
            r.expect(c, isFailure(Files.append(path, [9]), .denied), "appendFile to a read-only file")
            chmod(path, 0o600)
            r.count(c, "permissions")
        }
        r.expect(c, contents(path) == before, "a failed append changed the file")
    }

    // MARK: makeDir

    func makeDir(_ g: inout SplitMix, _ r: Recorder, _ root: String) {
        let c = "effects.make-dir"
        let parts = (0..<g.range(1, 4)).map { _ in FilesSuite.component(&g) }
        let path = root + "/" + parts.joined(separator: "/")
        r.expect(c, isFailure(Files.makeDir(""), .invalid), "makeDir of the empty path")
        if path.utf8.contains(0) {
            r.expect(c, isFailure(Files.makeDir(path), .invalid), "makeDir of a path with NUL")
            return
        }
        if FilesSuite.posixRefuses(root + "-oracle", parts) != nil {
            try? FileManager.default.removeItem(atPath: root + "-oracle")
            r.expect(c, isFailure(Files.makeDir(path)), "makeDir of a refused name")
            r.count(c, "refusedNames")
            return
        }
        try? FileManager.default.removeItem(atPath: root + "-oracle")
        let dirs = (1...parts.count).map { root + "/" + parts[0..<$0].joined(separator: "/") }
        // Some of the way there already, at a mode it must keep.
        let pre = g.below(parts.count)
        for d in dirs.prefix(pre) { mkdir(d, 0o755); chmod(d, 0o755) }
        func mode(_ p: String) -> mode_t { var st = stat(); stat(p, &st); return st.st_mode & 0o777 }
        let old = umask(g.elem([0o022, 0o077, 0o000]))
        let reply = Files.makeDir(path)
        umask(old)
        guard r.expect(c, reply == .done, "makeDir: \(reply)") else { return }
        r.expect(c, isDir(path), "after `done` there is no directory")
        for (i, d) in dirs.enumerated() {
            let want: mode_t = i < pre ? 0o755 : 0o700
            r.expect(c, mode(d) == want, "\(i < pre ? "an existing" : "a made") directory is mode \(String(mode(d), radix: 8)), not \(String(want, radix: 8))")
        }
        r.expect(c, Files.makeDir(path) == .done, "makeDir again: \(Files.makeDir(path))")
        r.count(c, "made", parts.count - pre)
        // In the way: a file, or a path under one.
        let file = path + "/f"
        FileManager.default.createFile(atPath: file, contents: Data([1]))
        r.expect(c, isFailure(Files.makeDir(file)), "makeDir over a file: \(Files.makeDir(file))")
        r.expect(c, isFailure(Files.makeDir(file + "/d")), "makeDir under a file: \(Files.makeDir(file + "/d"))")
        r.expect(c, !isDir(file), "a file became a directory")
        if g.chance(1, 4), getuid() != 0 {
            chmod(path, 0o555)
            r.expect(c, isFailure(Files.makeDir(path + "/d"), .denied), "makeDir in a read-only directory: \(Files.makeDir(path + "/d"))")
            chmod(path, 0o700)
            r.count(c, "permissions")
        }
    }

    // MARK: listDir

    func list(_ g: inout SplitMix, _ r: Recorder, _ root: String) {
        let c = "effects.list-dir"
        let dir = root + "/d"
        r.expect(c, isFailure(Files.list(dir), .notFound), "listDir of a missing directory: \(Files.list(dir))")
        mkdir(dir, 0o755)
        var made = Set<String>()
        for _ in 0..<g.weighted([(1, { _ in 0 }), (4, { $0.range(1, 12) }), (1, { $0.range(100, 300) })]) {
            let n = FilesSuite.component(&g)
            // A "/" makes it a path, not a name ("/x" under `dir` is "x"), so it isn't one to list.
            if n.utf8.contains(0) || n.utf8.contains(UInt8(ascii: "/")) || made.contains(where: { $0.lowercased() == n.lowercased() }) { continue }
            let p = dir + "/" + n
            let ok: Bool = switch g.below(4) {
            case 0: mkdir(p, 0o755) == 0
            case 1: symlink("nowhere", p) == 0
            default: FileManager.default.createFile(atPath: p, contents: Data([1]))
            }
            // A name APFS refuses, or one equal to another under its normalization, isn't made.
            if ok && FileManager.default.fileExists(atPath: p) || (try? FileManager.default.destinationOfSymbolicLink(atPath: p)) != nil {
                made.insert(n)
            }
        }
        guard case let .names(names) = Files.list(dir) else {
            r.fail(c, "listDir of a directory: \(Files.list(dir))")
            return
        }
        // FileManager's URL listing, read back through each URL's file-system representation:
        // the bytes the file system holds. (`contentsOfDirectory(atPath:)` decodes names as
        // NSString does, which drops one leading U+FEFF: "\u{FEFF}a" comes back as "a", a name
        // that isn't in the directory. That was the oracle's bug, not the host's.)
        let fm = ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                                includingPropertiesForKeys: nil)) ?? [])
            .map(Self.fileSystemName)
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        r.expect(c, names.map { Array($0.utf8) } == fm.map { Array($0.utf8) },
                 "listDir differs from FileManager: \(names.prefix(5)) vs \(fm.prefix(5))")
        r.expect(c, Set(names) == made, "listDir has \(names.count) names; the case made \(made.count); only listed: \(Set(names).subtracting(made).map { Array($0.unicodeScalars.map(\.value)) }), only made: \(made.subtracting(names).map { Array($0.unicodeScalars.map(\.value)) })")
        r.expect(c, zip(names, names.dropFirst()).allSatisfy { $0.utf8.lexicographicallyPrecedes($1.utf8) },
                 "listDir's names are not strictly sorted by UTF-8 bytes")
        r.count(c, "names", names.count)
        r.count(c, "leadingBOM", names.filter { $0.unicodeScalars.first == "\u{FEFF}" }.count)
        if let f = names.first(where: { FileManager.default.fileExists(atPath: dir + "/" + $0) && !isDir(dir + "/" + $0) }) {
            r.expect(c, isFailure(Files.list(dir + "/" + f), .invalid), "listDir of a file: \(Files.list(dir + "/" + f))")
        }
        r.expect(c, isFailure(Files.list(""), .invalid), "listDir of the empty path")
        r.expect(c, isFailure(Files.list(dir + "\0x"), .invalid), "listDir of a path with NUL")
        if getuid() != 0 {
            chmod(dir, 0o000)
            r.expect(c, isFailure(Files.list(dir), .denied), "listDir of an unreadable directory: \(Files.list(dir))")
            chmod(dir, 0o755)
        }
    }

    /// A listed URL's last component as the file system's bytes, not as Foundation decodes it.
    static func fileSystemName(_ u: URL) -> String {
        u.withUnsafeFileSystemRepresentation { p -> String in
            guard let p else { return u.lastPathComponent }
            let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(p).assumingMemoryBound(to: UInt8.self),
                                                  count: strlen(p)))
            let last = bytes.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: true).last ?? []
            return String(decoding: last, as: UTF8.self)
        }
    }

    func isDir(_ p: String) -> Bool {
        var st = stat()
        return lstat(p, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR
    }

    func exists(_ p: String) -> Bool {
        var st = stat()
        return lstat(p, &st) == 0
    }

    // MARK: deleteFile

    func delete(_ g: inout SplitMix, _ r: Recorder, _ root: String) {
        let c = "effects.delete-file"
        var n = FilesSuite.component(&g)
        if n.utf8.contains(0) {
            r.expect(c, isFailure(Files.delete(root + "/" + n), .invalid), "deleteFile of a path with NUL")
            return
        }
        if FilesSuite.posixRefuses(root + "-oracle", [n]) != nil { n = "f\(g.below(1000))" }
        try? FileManager.default.removeItem(atPath: root + "-oracle")
        let p = root + "/" + n
        let target = root + "/target"
        FileManager.default.createFile(atPath: target, contents: Data([7]))
        switch g.below(4) {
        case 0:
            mkdir(p, 0o755)
            r.expect(c, isFailure(Files.delete(p), .invalid), "deleteFile of a directory: \(Files.delete(p))")
            r.expect(c, isDir(p), "deleteFile removed a directory")
            r.count(c, "directories")
            return
        case 1:
            symlink(target, p)
            r.count(c, "links")
        case 2:
            symlink(root + "/missing", p)
            r.count(c, "danglingLinks")
        default:
            FileManager.default.createFile(atPath: p, contents: Data(FilesSuite.data(&g)))
            r.count(c, "files")
        }
        if g.chance(1, 4), getuid() != 0 {
            chmod(root, 0o555)
            r.expect(c, isFailure(Files.delete(p), .denied), "deleteFile in a read-only directory: \(Files.delete(p))")
            chmod(root, 0o755)
            r.expect(c, exists(p), "a refused delete removed the file")
        }
        let reply = Files.delete(p)
        r.expect(c, reply == .done, "deleteFile: \(reply)")
        r.expect(c, !exists(p), "after `done` the file is still there")
        r.expect(c, contents(target) == [7], "deleting a link touched its target")
        r.expect(c, isFailure(Files.delete(p), .notFound), "deleteFile again: \(Files.delete(p))")
        r.expect(c, isFailure(Files.delete(""), .invalid), "deleteFile of the empty path")
    }

    // MARK: watchFile

    func watch(_ g: inout SplitMix, _ r: Recorder, _ root: String) {
        let c = "subs.watch-file"
        let world = World(handlers: Handlers(table: [:]), devices: .inert)
        world.watchPeriodMs = g.elem([5, 10, 20])
        let period = world.watchPeriodMs
        // The look after a change comes sooner than the period (the live world: 250 ms after
        // one that saw a change, else every 2 s), or a whole period later.
        world.watchSettleMs = g.bool() ? period : g.elem([1, 2, period / 2])
        r.count(c, world.watchSettleMs < period ? "shortSettle" : "periodSettle")
        let events = Locked<[(UInt32, SubEvent, UInt64)]>([])
        world.send = { es in
            for case let .subEvent(id, e) in es { events.update { $0.append((id, e, HostClock.monoMs())) } }
        }
        let path = root + "/config.json"
        let id = UInt32(g.below(100))
        if g.bool() { FileManager.default.createFile(atPath: path, contents: Data("{}".utf8)) }
        world.run([], [.start(id: id, .watchFile(path: path))])
        // How long a change may take to be seen: a few polls, generously for a loaded machine.
        let settle = UInt32(max(150, period * 8) * 1000)
        usleep(UInt32(period * 3000))
        r.expect(c, events.value.isEmpty, "changed before anything changed: \(events.value.count)")

        for _ in 0..<g.range(2, 6) {
            events.value = []
            let op = g.below(9)
            let exists = FileManager.default.fileExists(atPath: path)
            var changes = 1
            switch op {
            case 0:  // write in place (truncate, then write: up to two changes)
                if let h = FileHandle(forWritingAtPath: path) {
                    h.truncateFile(atOffset: 0); h.write(Data("{\"key\":\"f13\"}".utf8)); h.closeFile()
                    changes = 2
                } else { FileManager.default.createFile(atPath: path, contents: Data("{}".utf8)) }
            case 1:  // Foundation touches the old file's metadata, then renames the new one over it
                try? Data("{\"x\":\(g.below(1000))}".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
                if exists { changes = 2 }
            case 2: _ = Files.append(path, [10])  // a new file is created, then written
                if !exists { changes = 2 }
            case 3:
                if exists { unlink(path) } else { changes = 0 }
            case 4: FileManager.default.createFile(atPath: path, contents: Data())
                if exists { changes = 2 }  // truncate and write are one call, but say up to two
            case 5:
                if exists {
                    var ts = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_NOW)), timespec(tv_sec: 0, tv_nsec: Int(UTIME_NOW))]
                    utimensat(AT_FDCWD, path, &ts, 0)
                } else { changes = 0 }
            case 6:
                if exists {
                    var st = stat()
                    stat(path, &st)
                    chmod(path, st.st_mode & 0o777 == 0o600 ? 0o644 : 0o600)
                } else { changes = 0 }
            default: changes = 0  // nothing, or a sibling file changes
                if g.bool() { FileManager.default.createFile(atPath: root + "/other", contents: Data([1])) }
            }
            usleep(settle)
            let got = events.value
            r.expect(c, got.allSatisfy { $0.0 == id && $0.1 == .changed }, "an event that is not this watch's `changed`: \(got.map { "\($0.0) \($0.1)" })")
            if changes == 0 {
                r.expect(c, got.isEmpty, "\(got.count) changed with no change (op \(op))")
                r.count(c, "quiet")
            } else {
                r.expect(c, !got.isEmpty && got.count <= changes, "\(got.count) changed for op \(op), allowed 1…\(changes)")
                r.count(c, "changes")
                if got.count > 1 { r.count(c, "seenTwice") }
            }
        }
        world.run([], [.stop(id: id)])
        events.value = []
        FileManager.default.createFile(atPath: path, contents: Data("after".utf8))
        usleep(settle)
        r.expect(c, events.value.isEmpty, "changed after the stop was handled")
        r.expect(c, world.running.isEmpty, "the watch still runs after its stop")
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "appendFile, listDir, deleteFile or watchFile under \(NSTemporaryDirectory())"
    }
}
