import AppKit
import CairnFrame
import Foundation

// The host's side of the outside world (docs/effects.md): the clock, the requests Lean asks
// for and the subscriptions it starts and stops. Lean decides everything (timers, which reply
// is delivered, which subscription is active); the host only reads the clock, runs requests
// with a small handler table and runs timers for subscriptions. Every assumption here is a
// claim in docs/trusted.md (^908–^915).

/// The clock Lean sees (^908).
public enum HostClock {
    /// Monotonic milliseconds: `CLOCK_MONOTONIC`, which on macOS keeps counting while the
    /// machine sleeps (a stopwatch keeps running through sleep).
    public static func monoMs() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000 }

    public static func now() -> Time {
        let wall = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
        return Time(mono: monoMs(), wall: wall, zone: Int32(TimeZone.current.secondsFromGMT()))
    }
}

/// Runs one request and answers it through `reply`, which the host calls exactly once.
public typealias RequestHandler = @Sendable (Request, _ reply: @escaping @Sendable (Reply) -> Void) -> Void

/// The requests the host can run, by `Request.kindCode`. Adding a kind is one entry here (and
/// its Lean constructor, encoding and `Reply.answers` case).
public struct Handlers: Sendable {
    public var table: [UInt8: RequestHandler]
    public init(table: [UInt8: RequestHandler]) { self.table = table }

    public static let standard = Handlers(table: [
        0: { r, reply in if case let .readFile(p) = r { reply(Files.read(p)) } },
        1: { r, reply in if case let .writeFile(p, d) = r { reply(Files.write(p, d)) } },
        2: { r, reply in if case let .playSound(n) = r { Sounds.play(n, reply) } },
        3: { r, reply in
            if case let .http(m, u, hs, b, t) = r {
                HTTP.run(method: m, url: u, headers: hs, body: b, timeoutMs: t, session: HTTP.session, reply)
            }
        },
    ])
}

/// Files for `readFile` and `writeFile` (^910, ^911).
public enum Files {
    /// A leading `~/` is the home directory; other paths are taken as given.
    public static func expand(_ path: String) -> String {
        path.hasPrefix("~/") ? NSHomeDirectory() + String(path.dropFirst(1)) : path
    }

    static func fault(_ error: Error) -> Reply {
        let e = error as NSError
        let posix = (e.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap {
            $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil
        }
        let f: Fault
        switch (e.domain, e.code, posix) {
        case (_, _, ENOENT?), (NSCocoaErrorDomain, NSFileReadNoSuchFileError, _),
             (NSCocoaErrorDomain, NSFileNoSuchFileError, _): f = .notFound
        case (_, _, EACCES?), (_, _, EPERM?), (NSCocoaErrorDomain, NSFileReadNoPermissionError, _),
             (NSCocoaErrorDomain, NSFileWriteNoPermissionError, _): f = .denied
        case (_, _, EISDIR?), (_, _, ENOTDIR?), (NSCocoaErrorDomain, NSFileReadInvalidFileNameError, _),
             (NSCocoaErrorDomain, NSFileWriteInvalidFileNameError, _): f = .invalid
        default: f = .other
        }
        return .failed(f, e.localizedDescription)
    }

    public static func read(_ path: String) -> Reply {
        guard !path.isEmpty else { return .failed(.invalid, "empty path") }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: expand(path)), options: .mappedIfSafe)
            guard data.count <= Int(UInt32.max) else { return .failed(.invalid, "file too large") }
            return .bytes([UInt8](data))
        } catch {
            return fault(error)
        }
    }

    /// Replaces the file atomically (a temporary file in the same directory, then rename), after
    /// creating missing parent directories.
    public static func write(_ path: String, _ bytes: [UInt8]) -> Reply {
        guard !path.isEmpty else { return .failed(.invalid, "empty path") }
        let url = URL(fileURLWithPath: expand(path))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(bytes).write(to: url, options: .atomic)
            return .done
        } catch {
            return fault(error)
        }
    }
}

/// Named system sounds for `playSound` (^912).
public enum Sounds {
    public static func play(_ name: String, _ reply: @escaping @Sendable (Reply) -> Void) {
        DispatchQueue.main.async {
            guard let s = NSSound(named: NSSound.Name(name)) else {
                reply(.failed(.notFound, "no sound named \(name)"))
                return
            }
            // A sound object plays once at a time; a copy lets the same name overlap itself.
            let copy = (s.copy() as? NSSound) ?? s
            reply(copy.play() ? .done : .failed(.other, "could not play \(name)"))
        }
    }
}

/// HTTP for `http` (^913): an ephemeral session (no cookies, cache or credentials kept).
public enum HTTP {
    public static let session = URLSession(configuration: .ephemeral)

    public static func run(method: String, url: String, headers: [Header], body: [UInt8],
                           timeoutMs: UInt32, session: URLSession,
                           _ reply: @escaping @Sendable (Reply) -> Void) {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            reply(.failed(.invalid, "not an http(s) URL: \(url)"))
            return
        }
        guard !method.isEmpty, method.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) else {
            reply(.failed(.invalid, "bad method: \(method)"))
            return
        }
        var req = URLRequest(url: u)
        req.httpMethod = method
        for h in headers { req.addValue(h.value, forHTTPHeaderField: h.name) }
        if !body.isEmpty { req.httpBody = Data(body) }
        req.timeoutInterval = timeoutMs == 0 ? 60 : Double(timeoutMs) / 1000
        session.dataTask(with: req) { data, response, error in
            if let error {
                let e = error as NSError
                let f: Fault = switch (e.domain, e.code) {
                case (NSURLErrorDomain, NSURLErrorTimedOut): .timeout
                case (NSURLErrorDomain, NSURLErrorBadURL), (NSURLErrorDomain, NSURLErrorUnsupportedURL): .invalid
                case (NSURLErrorDomain, _): .network
                default: .other
                }
                reply(.failed(f, e.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                reply(.failed(.other, "not an HTTP response"))
                return
            }
            let hs = http.allHeaderFields.compactMap { k, v -> Header? in
                guard let k = k as? String else { return nil }
                return Header(k, "\(v)")
            }.sorted { $0.name < $1.name }
            reply(.http(status: UInt32(max(0, http.statusCode)), headers: hs, body: [UInt8](data ?? Data())))
        }.resume()
    }
}

/// Runs the requests and subscriptions of each published frame. Requests run concurrently and
/// answer through `send`, each exactly once (^914); `every` subscriptions are dispatch timers
/// on one serial queue, so after a `stop` is handled no tick of it is sent (^915).
public final class World: @unchecked Sendable {
    public var handlers: Handlers
    private let queue = DispatchQueue(label: "cairn.world")
    private let lock = NSLock()
    private var timers: [UInt32: DispatchSourceTimer] = [:]
    /// Bumped by `reset`: replies and ticks from before it are dropped.
    private var generation = 0
    /// Where replies and ticks go (the engine's `send`).
    var send: (@Sendable ([Event]) -> Void)?

    public init(handlers: Handlers = .standard) { self.handlers = handlers }

    /// The frame's effects and subscription commands, in order. Called on the Lean thread.
    func run(_ effects: [Effect], _ subs: [SubCmd]) {
        lock.lock()
        let gen = generation
        lock.unlock()
        for e in effects {
            guard case let .request(id, r) = e else { continue }
            perform(id, r, gen)
        }
        if !subs.isEmpty { queue.sync { for c in subs { apply(c, gen) } } }
    }

    private func perform(_ id: UInt32, _ r: Request, _ gen: Int) {
        let once = Once()
        let reply: @Sendable (Reply) -> Void = { [weak self] rep in
            guard once.take(), let self else { return }
            self.lock.lock()
            let current = self.generation == gen
            self.lock.unlock()
            if current { self.send?([.reply(id: id, rep)]) }
        }
        guard let h = handlers.table[r.kindCode] else {
            reply(.failed(.invalid, "no handler for request kind \(r.kindCode)"))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { h(r, reply) }
    }

    private func apply(_ c: SubCmd, _ gen: Int) {
        switch c {
        case let .start(id, .every(ms)):
            timers.removeValue(forKey: id)?.cancel()
            let t = DispatchSource.makeTimerSource(queue: queue)
            let period = DispatchTimeInterval.milliseconds(Int(max(1, ms)))
            t.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.send?([.subEvent(id: id, .tick)]) }
            timers[id] = t
            t.resume()
        case let .stop(id):
            timers.removeValue(forKey: id)?.cancel()
        }
    }

    /// The app starts over (`Engine.restart`): stop every subscription and drop answers to
    /// requests made before.
    func reset() {
        lock.lock()
        generation += 1
        lock.unlock()
        queue.sync {
            for t in timers.values { t.cancel() }
            timers.removeAll()
        }
    }

    /// The ids of running subscriptions (tests).
    public var running: Set<UInt32> { queue.sync { Set(timers.keys) } }
}

/// True the first time only.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
