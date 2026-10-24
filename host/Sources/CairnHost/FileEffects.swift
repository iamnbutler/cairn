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

    /// A failed append as a reply: `posix`'s fault, with the text Foundation gives Yap's
    /// `TranscriptLog.append` for the same errno. Opening fails as its fallback
    /// `Data.write(to:options: .atomic)` does, naming the file and its folder; a write part way
    /// fails as `FileHandle.write(contentsOf:)` does, naming neither. A directory reads as
    /// missing there: the atomic write's rename finds none (probed on macOS 27).
    static func appendFailure(_ e: Int32, opening path: String?) -> Reply {
        guard case let .failed(f, _) = posix(e, "") else { return .failed(.other, "") }
        let code: Int = switch e {
        case ENOENT, EISDIR: NSFileNoSuchFileError
        case EPERM, EACCES: NSFileWriteNoPermissionError
        case ENAMETOOLONG: NSFileWriteInvalidFileNameError
        case ENOSPC, EDQUOT: NSFileWriteOutOfSpaceError
        case EROFS: NSFileWriteVolumeReadOnlyError
        case EEXIST: NSFileWriteFileExistsError
        default: NSFileWriteUnknownError
        }
        var info: [String: Any] = [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain,
                                                                  code: Int(e == EISDIR ? ENOENT : e))]
        if let path { info[NSFilePathErrorKey] = path }
        return .failed(f, NSError(domain: NSCocoaErrorDomain, code: code, userInfo: info).localizedDescription)
    }

    /// Appends `bytes` to the file, creating it (mode 600: transcripts are private) and missing
    /// parent directories (mode 700, as Yap makes its folders). Not atomic: a failure part way
    /// (a full disk) can leave a prefix of the bytes appended, as Yap's own log can. `done` once
    /// every byte is written. Failures say what Foundation says to Yap (`appendFailure`).
    public static func append(_ path: String, _ bytes: [UInt8]) -> Reply {
        if let bad = invalid(path) { return bad }
        let p = expand(path)
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: p).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return fault(error)
        }
        let fd = open(p, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        if fd < 0 { return appendFailure(errno, opening: p) }
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
                return appendFailure(errno, opening: nil)
            }
            off += n
        }
        return .done
    }

    /// Creates the directory and its missing parents, each mode 700 (Yap's
    /// `createDirectory(…, attributes: [.posixPermissions: 0o700])`). `done` when it is there
    /// already; a file in the way is `invalid`, a read-only parent `denied`.
    public static func makeDir(_ path: String) -> Reply {
        if let bad = invalid(path) { return bad }
        do {
            try FileManager.default.createDirectory(atPath: expand(path), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            return .done
        } catch {
            return fault(error)
        }
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
