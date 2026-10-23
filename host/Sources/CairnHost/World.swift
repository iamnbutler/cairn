import AppKit
import CairnFrame
import Foundation

// The host's side of the outside world (docs/effects.md): the clock, the requests Lean asks
// for and the subscriptions it starts and stops. Lean decides everything (timers, which reply
// is delivered, which subscription is active); the host only reads the clock, runs requests
// with a small handler table and runs timers for subscriptions. Every assumption here is a
// claim in docs/trusted.md (^908–^915, ^960–).

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
        4: { r, reply in if case let .appendFile(p, d) = r { reply(Files.append(p, d)) } },
        5: { r, reply in if case let .listDir(p) = r { reply(Files.list(p)) } },
        6: { r, reply in if case let .deleteFile(p) = r { reply(Files.delete(p)) } },
        7: { _, reply in reply(Apps.frontmost()) },
        8: { r, reply in if case let .permission(p, prompt) = r { Permissions.check(p, prompt: prompt, .live, reply) } },
        12: { r, reply in if case let .openItem(t) = r { reply(Opening.open(t)) } },
        13: { r, reply in if case let .appRunning(b) = r { reply(Opening.running(b)) } },
        14: { r, reply in if case let .readDefault(d, k) = r { reply(Opening.readDefault(d, k)) } },
    ])
}

/// What the host's world reaches through: the microphone, the keyboard, typing into other apps,
/// secrets and the network. Tests swap in stubs, so `make check` never records, listens to keys,
/// types into another app or reads a real secret.
public struct Devices: Sendable {
    public var microphone: Microphone
    public var keys: KeySource
    public var typist: Typist
    public var secrets: SecretSource
    public var session: URLSession

    public init(microphone: Microphone, keys: KeySource, typist: Typist, secrets: SecretSource, session: URLSession) {
        self.microphone = microphone; self.keys = keys; self.typist = typist; self.secrets = secrets
        self.session = session
    }

    public static let live = Devices(microphone: .live, keys: .live, typist: .live, secrets: .live, session: HTTP.session)

    /// Devices that touch nothing: no microphone, no keys, no Accessibility, no secrets, and a
    /// session no request reaches the network through. For tests.
    public static let inert = Devices(
        microphone: Microphone { _ throws(ReplyError) in throw ReplyError(.denied, "inert microphone") },
        keys: KeySource(trusted: { false }, start: { _ in {} }),
        typist: Typist(trusted: { false }, exists: { _ in false }, activate: { _, _ in false }, post: { _, _ in }),
        secrets: SecretSource(environment: { _ in nil }, readFile: { _ in nil }),
        session: {
            let c = URLSessionConfiguration.ephemeral
            c.protocolClasses = [RefuseProtocol.self]
            return URLSession(configuration: c)
        }())
}

/// Fails every request without sending it.
final class RefuseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
    }
    override func stopLoading() {}
}

extension Handlers {
    /// `typeText`, `upload` and `forgetClip`, which reach the world's clips and devices.
    public static func devices(_ clips: Clips, _ d: Devices) -> [UInt8: RequestHandler] {
        [
            9: { r, reply in
                if case let .typeText(pid, text, ret) = r { reply(Typing.type(pid: pid, text: text, pressReturn: ret, d.typist)) }
            },
            10: { r, reply in
                if case let .upload(m, u, hs, sec, body, t) = r {
                    Upload.run(method: m, url: u, headers: hs, secret: sec, body: body, timeoutMs: t,
                               clips: clips, secrets: d.secrets, session: d.session, reply)
                }
            },
            11: { r, reply in if case let .forgetClip(c) = r { reply(clips.forget(c)) } },
        ]
    }
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
        // EILSEQ: a name the file system refuses (APFS: unassigned code points, noncharacters).
        case (_, _, EISDIR?), (_, _, ENOTDIR?), (_, _, EILSEQ?), (_, _, ENAMETOOLONG?), (NSCocoaErrorDomain, NSFileReadInvalidFileNameError, _),
             (NSCocoaErrorDomain, NSFileWriteInvalidFileNameError, _): f = .invalid
        default: f = .other
        }
        return .failed(f, e.localizedDescription)
    }

    /// Why `path` can't name a file, if it can't: empty, or containing NUL (which the file
    /// system would silently cut the path at).
    static func invalid(_ path: String) -> Reply? {
        if path.isEmpty { return .failed(.invalid, "empty path") }
        if path.utf8.contains(0) { return .failed(.invalid, "NUL in path") }
        return nil
    }

    public static func read(_ path: String) -> Reply {
        if let bad = invalid(path) { return bad }
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
        if let bad = invalid(path) { return bad }
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
    /// The sound `name` names: a system sound (`/System/Library/Sounds`) or one in the app's
    /// bundle, by its plain name. A name with `.` or `/` is no sound (`NSSound(named:)` would
    /// read "Morse.x" as Morse with an extension). Main thread.
    @MainActor public static func lookup(_ name: String) -> NSSound? {
        name.isEmpty || name.contains(where: { $0 == "." || $0 == "/" || $0 == "\0" }) ? nil
            : NSSound(named: NSSound.Name(name))
    }

    public static func play(_ name: String, _ reply: @escaping @Sendable (Reply) -> Void) {
        DispatchQueue.main.async {
            guard let s = lookup(name) else {
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
        // Header names are RFC 9110 tokens; values have no CR, LF or NUL (no header injection).
        let tchar = Set("!#$%&'*+-.^_`|~".utf8)
        for h in headers {
            guard !h.name.isEmpty, h.name.utf8.allSatisfy({ $0 < 0x80 && (tchar.contains($0) || Character(Unicode.Scalar($0)).isLetter || Character(Unicode.Scalar($0)).isNumber) }) else {
                reply(.failed(.invalid, "bad header name: \(h.name)"))
                return
            }
            guard !h.value.utf8.contains(where: { $0 == 0x0D || $0 == 0x0A || $0 == 0 }) else {
                reply(.failed(.invalid, "bad header value for \(h.name)"))
                return
            }
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
/// answer through `send`, each exactly once (^914). Subscriptions start and stop on one serial
/// queue, and every event they send is sent from it, so after a `stop` is handled none of its
/// events is sent (^915, ^963, ^966, ^969): `every` is a dispatch timer, `watchFile` a dispatch
/// timer that polls the file, `record` the microphone and `globalKey` the key monitors, whose
/// callbacks hop onto the queue and are dropped once their subscription has stopped.
public final class World: @unchecked Sendable {
    public var handlers: Handlers
    private let queue = DispatchQueue(label: "cairn.world")
    private let lock = NSLock()
    /// Running subscriptions: how to stop each.
    private var running_: [UInt32: () -> Void] = [:]
    /// How often `watchFile` looks at its file.
    public var watchPeriodMs = 250
    /// Bumped by `reset`: replies and ticks from before it are dropped.
    private var generation = 0
    /// Where replies and ticks go (the engine's `send`).
    public var send: (@Sendable ([Event]) -> Void)?

    /// Every recording, by clip id (`record`, `upload`'s `wav` parts, `forgetClip`).
    public let clips = Clips()
    public let devices: Devices

    /// `handlers`, plus the device handlers (`Handlers.devices`) for kinds it has none for.
    public init(handlers: Handlers = .standard, devices: Devices = .live) {
        self.devices = devices
        var h = handlers
        for (k, v) in Handlers.devices(clips, devices) where h.table[k] == nil { h.table[k] = v }
        self.handlers = h
    }

    /// The frame's effects and subscription commands, in order. Called on the Lean thread.
    public func run(_ effects: [Effect], _ subs: [SubCmd]) {
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
            // Sent with the lock held, so a `reset` that has returned has no reply of before
            // still on its way (`send` only enqueues; it never calls back in here).
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.generation == gen { self.send?([.reply(id: id, rep)]) }
        }
        guard let h = handlers.table[r.kindCode] else {
            reply(.failed(.invalid, "no handler for request kind \(r.kindCode)"))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { h(r, reply) }
    }

    private func apply(_ c: SubCmd, _ gen: Int) {
        switch c {
        case let .start(id, sub):
            running_.removeValue(forKey: id)?()
            running_[id] = start(id, sub)
        case let .stop(id):
            running_.removeValue(forKey: id)?()
        }
    }

    /// Starts `sub` on the queue; returns how to stop it.
    private func start(_ id: UInt32, _ sub: Sub) -> () -> Void {
        switch sub {
        case let .every(ms):
            let t = DispatchSource.makeTimerSource(queue: queue)
            let period = DispatchTimeInterval.milliseconds(Int(max(1, ms)))
            t.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.send?([.subEvent(id: id, .tick)]) }
            t.resume()
            return { t.cancel() }
        case let .watchFile(path):
            var last = FileSignature.of(path)
            let t = DispatchSource.makeTimerSource(queue: queue)
            let period = DispatchTimeInterval.milliseconds(max(1, watchPeriodMs))
            t.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(5))
            t.setEventHandler { [weak self] in
                let now = FileSignature.of(path)
                guard now != last else { return }
                last = now
                self?.send?([.subEvent(id: id, .changed)])
            }
            t.resume()
            return { t.cancel() }
        case let .record(clip):
            return record(id, clip)
        case let .globalKey(code, modifier):
            return globalKey(id, code, modifier)
        }
    }

    /// Records into `clip`: the samples into `clips` from the audio thread, their levels to
    /// Lean from the queue. Fails with a `failed` event (and an empty, finished clip) when the
    /// microphone can't start.
    private func record(_ id: UInt32, _ clip: UInt32) -> () -> Void {
        let live = Guarded(true)
        let meter = Guarded(LevelMeter())
        let clips = self.clips
        clips.begin(clip)
        do {
            let stopMic = try devices.microphone.start { [weak self] samples in
                let kept = clips.append(clip, samples)
                let batch = Array(samples)
                self?.queue.async { [weak self] in
                    guard let self, live.value else { return }
                    guard kept else {
                        live.value = false
                        self.send?([.subEvent(id: id, .failed(.other, "clip \(clip) is full or gone"))])
                        return
                    }
                    let (peak, windows) = meter.update { $0.feed(batch) }
                    self.send?([.subEvent(id: id, .audio(frames: UInt32(batch.count), peak: peak, windows: windows))])
                }
            }
            return {
                live.value = false
                stopMic()
                clips.finish(clip)
            }
        } catch {
            clips.finish(clip)
            send?([.subEvent(id: id, .failed(error.fault, error.message))])
            return {}
        }
    }

    /// Watches the hotkey (Yap's PushToTalk). Without Accessibility nothing is installed and
    /// the subscription reports `failed denied` once.
    private func globalKey(_ id: UInt32, _ code: UInt32, _ modifier: UInt32?) -> () -> Void {
        guard code <= UInt32(UInt16.max) else {
            send?([.subEvent(id: id, .failed(.invalid, "no key code \(code)"))])
            return {}
        }
        guard devices.keys.trusted() else {
            send?([.subEvent(id: id, .failed(.denied, "Accessibility is not granted, so the app cannot watch keys"))])
            return {}
        }
        let live = Guarded(true)
        let watch = Guarded(KeyWatch(code: UInt16(code), modifier: modifier.map(UInt.init)))
        let stop = devices.keys.start { [weak self] e in
            self?.queue.async { [weak self] in
                guard let self, live.value, let ev = watch.update({ $0.handle(e) }) else { return }
                self.send?([.subEvent(id: id, ev)])
            }
        }
        return {
            live.value = false
            stop()
        }
    }

    /// The app starts over (`Engine.restart`): stop every subscription and drop answers to
    /// requests made before.
    public func reset() {
        lock.lock()
        generation += 1
        lock.unlock()
        queue.sync {
            for stop in running_.values { stop() }
            running_.removeAll()
        }
        clips.reset()
    }

    /// The ids of running subscriptions (tests).
    public var running: Set<UInt32> { queue.sync { Set(running_.keys) } }
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
