import CairnFrame
import Foundation

// `appendFile`, `listDir` and `deleteFile` (docs/effects.md), and the polling behind the
// `watchFile` subscription. Trusted: claims ^960–^963 in docs/trusted.md.

extension Files {
    /// A failed POSIX call as a reply: the same faults `fault` gives Foundation's errors.
    static func posix(_ e: Int32, _ what: String) -> Reply {
        let f: Fault = switch e {
        case ENOENT: .notFound
        case EACCES, EPERM: .denied
        case EISDIR, ENOTDIR, EILSEQ, ENAMETOOLONG: .invalid
        default: .other
        }
        return .failed(f, "\(what): \(String(cString: strerror(e)))")
    }

    /// Appends `bytes` to the file, creating it (mode 600: transcripts are private) and missing
    /// parent directories. Not atomic: a failure part way (a full disk) can leave a prefix of
    /// the bytes appended, as Yap's own log can. `done` once every byte is written.
    public static func append(_ path: String, _ bytes: [UInt8]) -> Reply {
        if let bad = invalid(path) { return bad }
        let p = expand(path)
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: p).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            return fault(error)
        }
        let fd = open(p, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        if fd < 0 { return posix(errno, "open") }
        defer { close(fd) }
        var fileStat = stat()
        if fstat(fd, &fileStat) == 0, fileStat.st_mode & S_IFMT != S_IFREG {
            return .failed(.invalid, "not a regular file")
        }
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + off, bytes.count - off) }
            if n < 0 {
                if errno == EINTR { continue }
                return posix(errno, "write")
            }
            off += n
        }
        return .done
    }

    /// The names in the directory, without `.` and `..`, sorted by their UTF-8 bytes. A name
    /// that is not valid UTF-8 (APFS allows none; other file systems might) is left out.
    public static func list(_ path: String) -> Reply {
        if let bad = invalid(path) { return bad }
        guard let dir = opendir(expand(path)) else { return posix(errno, "opendir") }
        defer { closedir(dir) }
        var names: [String] = []
        while true {
            errno = 0
            guard let ent = readdir(dir) else {
                if errno != 0 { return posix(errno, "readdir") }
                break
            }
            let name = withUnsafeBytes(of: ent.pointee.d_name) { raw -> String? in
                let bytes = raw.prefix(Int(ent.pointee.d_namlen))
                return String(validating: bytes, as: UTF8.self)
            }
            guard let name, name != ".", name != ".." else { continue }
            names.append(name)
        }
        names.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        guard names.count <= Int(UInt32.max) else { return .failed(.invalid, "too many names") }
        return .names(names)
    }

    /// Removes a file or a symbolic link (not what it points to). A directory is `invalid` and
    /// is never removed; a missing file is `notFound`.
    public static func delete(_ path: String) -> Reply {
        if let bad = invalid(path) { return bad }
        let p = expand(path)
        var st = stat()
        if lstat(p, &st) != 0 { return posix(errno, "lstat") }
        if st.st_mode & S_IFMT == S_IFDIR { return .failed(.invalid, "is a directory") }
        if unlink(p) != 0 { return posix(errno, "unlink") }
        return .done
    }
}

/// What `watchFile` compares between polls: everything a write, a replacement (rename over it),
/// a creation, a removal or a `touch` changes.
struct FileSignature: Equatable {
    var exists = false
    var dev: Int32 = 0
    var ino: UInt64 = 0
    var size: Int64 = 0
    var mtime = timespec()
    var ctime = timespec()

    static func == (a: Self, b: Self) -> Bool {
        a.exists == b.exists && a.dev == b.dev && a.ino == b.ino && a.size == b.size
            && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
            && a.ctime.tv_sec == b.ctime.tv_sec && a.ctime.tv_nsec == b.ctime.tv_nsec
    }

    /// `stat` follows a symbolic link, so a config file linked from elsewhere is watched where
    /// it lives.
    static func of(_ path: String) -> FileSignature {
        var st = stat()
        guard !path.isEmpty, !path.utf8.contains(0), stat(Files.expand(path), &st) == 0 else { return FileSignature() }
        return FileSignature(exists: true, dev: st.st_dev, ino: st.st_ino, size: st.st_size,
                             mtime: st.st_mtimespec, ctime: st.st_ctimespec)
    }
}
