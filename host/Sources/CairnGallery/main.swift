import AppKit
import CLean
import CairnCapture
import CairnFrame
import CairnHost
import CairnRender
import Metal
import QuartzCore

// Gallery (lean/Examples/Gallery.lean): image tiles loaded with `loadImage` (docs/effects.md,
// "Images").
//   CairnGallery               open the window
//   CairnGallery --selftest    drive the host headlessly through its real threads and check it
//   CairnGallery --demo-resize open the window, then widen and narrow it over 12 s so the tile
//                              grid reflows (for the demo video; docs/media.md)
//   CairnGallery --demo-min-size  open the window, then drag it smaller than its minimum size
//                              (1020 × 536, ^511) and back over 12 s: it stops there
//
// The demos resize the window as a person dragging its corner does: each size is proposed to
// the window's delegate (the host's `WindowSizer`, ^1010) before it is set.
//
// Load 24 (^506) asks for 24 thumbnails from `https://slow.cairn.test/many/<i>.png`, which
// `SlowServer` answers from the bundled pictures after a second or two, so the
// runtime's cap on requests in flight (six) and Cancel (^507) can be watched.
//
// The app names its bundled pictures by paths relative to its resources (`images/…`), so the
// host starts there.

let gallery = LeanApp(
    module: runtime_initialize_cairn_Examples_Gallery_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

let size = Size(w: 1120, h: 560)
let args = CommandLine.arguments

guard let resources = Bundle.module.resourcePath, FileManager.default.changeCurrentDirectoryPath(resources) else {
    FileHandle.standardError.write("CairnGallery: no resource bundle\n".data(using: .utf8)!)
    exit(1)
}

if let code = MapCapture.main(args, size: size, core: { LeanCore(gallery) }) { exit(code) }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("FAIL: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
    exit(0)
}

/// The demo server behind `slow.cairn.test`: answers each request with one of the bundled
/// pictures after 1.2–2.4 s, and counts how many it is serving at once. A stopped request
/// (its `URLSession` task cancelled) is never answered. Other hosts go to the network, or with
/// `offline` fail as if there were none.
final class SlowServer: URLProtocol, @unchecked Sendable {
    static let host = "slow.cairn.test"
    nonisolated(unsafe) static var offline = false
    private static let lock = NSLock()
    nonisolated(unsafe) private static var serving = 0
    nonisolated(unsafe) private static var counts = (most: 0, served: 0, stopped: 0)
    static var stats: (most: Int, served: Int, stopped: Int) { lock.withLock { counts } }
    static var now: Int { lock.withLock { serving } }
    static let pictures = ["images/ridge.png", "images/tide.jpg", "images/moss.gif"].compactMap {
        FileManager.default.contents(atPath: $0)
    }

    private var work: DispatchWorkItem?
    private var open = false

    override class func canInit(with request: URLRequest) -> Bool { offline || request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == Self.host else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
            return
        }
        Self.lock.withLock {
            Self.serving += 1
            Self.counts.most = max(Self.counts.most, Self.serving)
        }
        open = true
        let n = Int(url.deletingPathExtension().lastPathComponent) ?? 0
        let body = Self.pictures.isEmpty ? Data() : Self.pictures[n % Self.pictures.count]
        let work = DispatchWorkItem { [self] in
            guard close(stopped: false) else { return }
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(1200 + (n * 331) % 1200), execute: work)
    }

    override func stopLoading() {
        work?.cancel()
        _ = close(stopped: true)
    }

    /// Ends this request's count once; false if it had already ended.
    private func close(stopped: Bool) -> Bool {
        Self.lock.withLock {
            guard open else { return false }
            open = false
            Self.serving -= 1
            if stopped { Self.counts.stopped += 1 } else { Self.counts.served += 1 }
            return true
        }
    }

    /// A session that sends `slow.cairn.test` here.
    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [SlowServer.self] + (c.protocolClasses ?? [])
        return URLSession(configuration: c)
    }

    static func devices(_ base: Devices) -> Devices {
        Devices(microphone: base.microphone, keys: base.keys, typist: base.typist, secrets: base.secrets,
                session: session())
    }
}

@MainActor
enum SelfTest {
    static func run() {
        // Inert devices but the demo server: the https tile fails without touching the network.
        SlowServer.offline = true
        let engine = Engine(size: size, scalePercent: 200,
                            world: World(handlers: .standard, devices: SlowServer.devices(.inert))) {
            LeanCore(gallery)
        }
        let view = HostView(engine: engine, renderer: NullRenderer(),
                            size: NSSize(width: CGFloat(size.w), height: CGFloat(size.h)))
        engine.start()
        guard engine.wait(through: 0) != nil else { fail("no first frame") }

        func texts() -> [String] {
            engine.latest?.frame.draws.compactMap { if case let .text(_, _, _, s) = $0 { s } else { nil } } ?? []
        }
        func images() -> [(Rect, String)] {
            engine.latest?.frame.draws.compactMap { if case let .image(r, _, s) = $0 { (r, s) } else { nil } } ?? []
        }
        func until(_ what: String, timeout: Double = 5, _ ok: ([String]) -> Bool) {
            let deadline = Date(timeIntervalSinceNow: timeout)
            while !ok(texts()) {
                if Date() > deadline { fail("\(what): texts \(texts())") }
                _ = engine.wait(through: engine.send([.pointerMove(Point(x: 1, y: 1))]))
                usleep(1000)
            }
            view.applyLatestFrame()
        }
        func click(_ id: String) {
            guard let node = engine.latest?.frame.ax.first(where: { $0.control?.label == id }) else {
                fail("\(id) not in frame")
            }
            let c = Point(x: node.rect.x + node.rect.w / 2, y: node.rect.y + node.rect.h / 2)
            _ = engine.wait(through: engine.send([.pointerMove(c), .pointerDown(c, .primary, clicks: 1, Mods()),
                                                  .pointerUp(c, .primary, Mods())]))
            view.applyLatestFrame()
        }
        func count(_ s: String) -> Int { texts().filter { $0 == s }.count }

        // Launch: three pictures load (tide is stored 320 × 480, turned by its EXIF
        // orientation), the text file and the missing file fail, the URL is offline here.
        let t0 = hostNow()
        until("every tile answered") {
            $0.filter { $0 == "480 × 320 px" }.count == 2 && $0.contains("240 × 240 px")
                && $0.contains("Not an image") && $0.contains("Not found") && $0.contains("Offline")
        }
        let loadMs = (hostNow() - t0) * 1000
        let drawn = images()
        if drawn.count != 3 { fail("image draws \(drawn)") }
        if !drawn.allSatisfy({ $0.0.w == 196 && $0.0.h == 147 }) { fail("image boxes \(drawn)") }
        for src in ["images/ridge.png", "images/tide.jpg", "images/moss.gif"] {
            guard let e = ImageStore.shared.entry(src) else { fail("\(src) not kept") }
            if src == "images/tide.jpg", (e.pixels.width, e.pixels.height) != (480, 320) { fail("tide not turned: \(e.pixels.width)×\(e.pixels.height)") }
        }

        // Reload: every source again, past the cache; the same answers come back.
        click("^501")
        until("reloaded") {
            $0.contains("Reloads: 1") && $0.filter { $0 == "480 × 320 px" }.count == 2 && $0.contains("Not found")
        }
        // Fit cycles; the boxes stay 196 × 147.
        click("^502")
        until("contain") { $0.contains("Fit: Contain") }
        if !images().allSatisfy({ $0.0.w == 196 && $0.0.h == 147 }) { fail("boxes moved on Fit: \(images())") }
        // The tile grid follows the window (^510): at 1600 × 900 the three columns become five
        // and each picture's box grows to 216 × 162; back at 1120 × 560 it is three again.
        _ = engine.wait(through: engine.send([.resize(Size(w: 1600, h: 900))]))
        let wide = images()
        if wide.count != 3 || !wide.allSatisfy({ $0.0.w == 216 && $0.0.h == 162 }) { fail("boxes at 1600 × 900: \(wide)") }
        if Set(wide.map { $0.0.y }).count != 1 { fail("not one row of pictures at 1600 × 900: \(wide)") }
        _ = engine.wait(through: engine.send([.resize(size)]))
        if !images().allSatisfy({ $0.0.w == 196 && $0.0.h == 147 }) { fail("boxes after resizing back: \(images())") }
        if count("Offline") != 1 { fail("the URL tile: \(texts())") }
        // The window asks for its smallest size (^511), where each picture's box is 180 × 135.
        guard let w = engine.latest?.frame.windowIndex, let minSize = engine.latest?.frame.surfaces[w].minSize,
              minSize == Size(w: 1020, h: 536) else { fail("window minimum size") }
        _ = engine.wait(through: engine.send([.resize(minSize)]))
        if !images().allSatisfy({ $0.0.w == 180 && $0.0.h == 135 }) { fail("boxes at the minimum size: \(images())") }
        _ = engine.wait(through: engine.send([.resize(size)]))

        // Load 24: six at a time, the rest queued in Lean's runtime, never more than six at the server.
        click("^506")
        until("six in flight") { $0.contains("In flight 6 of 6 · queued 18") && $0.contains("Loaded 0 of 24 · cancelled 0 · evicted 0") }
        until("some loaded", timeout: 10) { $0.contains { $0.hasPrefix("In flight 6 of 6") } && !$0.contains { $0.hasPrefix("Loaded 0 of") } }
        // Cancel: those being fetched are stopped at the server, the rest never asked for.
        click("^507")
        until("cancelled") { $0.contains("In flight 0 of 6 · queued 0") && $0.contains { $0.hasPrefix("Loaded") && !$0.contains("cancelled 0 ·") } }
        let deadline = Date(timeIntervalSinceNow: 5)
        while SlowServer.now > 0 { if Date() > deadline { fail("server still serving \(SlowServer.now)") }; usleep(1000) }
        let afterCancel = SlowServer.stats
        if afterCancel.stopped == 0 { fail("Cancel stopped nothing at the server: \(afterCancel)") }
        if afterCancel.served + afterCancel.stopped >= 24 { fail("the queue reached the server after Cancel: \(afterCancel)") }
        // Load 24 again, to the end. The image cache's budget (8 MiB, ^1011) holds the tiles and
        // the twelve thumbnails on screen: the host drops most of the other page's, and the app
        // counts them evicted (^513).
        func settled(_ texts: [String]) -> (loaded: Int, evicted: Int)? {
            guard texts.contains("In flight 0 of 6 · queued 0"),
                  let line = texts.first(where: { $0.hasPrefix("Loaded ") }) else { return nil }
            let n = line.split(separator: " ").compactMap { Int($0) }
            guard n.count == 4, n[1] == 24, n[2] == 0, n[0] + n[3] == 24 else { return nil }
            return (n[0], n[3])
        }
        click("^506")
        until("all loaded or evicted", timeout: 20) { settled($0) != nil }
        guard let first = settled(texts()), first.evicted > 0 else { fail("nothing evicted under the budget: \(texts())") }
        // Every image drawn has its pixels in the store.
        func drawnHeld() {
            for (_, src) in images() where ImageStore.shared.entry(src) == nil { fail("\(src) drawn as loaded, but the store dropped it") }
        }
        drawnHeld()
        if images().filter({ $0.1.hasPrefix("https://slow.cairn.test/") }).count != 12 { fail("page 1 thumbnails: \(images())") }
        // Next page (^512): the dropped thumbnails there load again; page 1's are dropped in turn.
        click("^512")
        until("page 2 loaded", timeout: 20) {
            $0.contains("Page 2 of 2") && settled($0) != nil
                && images().filter({ $0.1.hasPrefix("https://slow.cairn.test/many/") }).count == 12
        }
        let page2 = images().map(\.1).filter { $0.hasPrefix("https://slow.cairn.test/") }
        if !page2.allSatisfy({ Int(($0 as NSString).deletingPathExtension.split(separator: "/").last ?? "") ?? 0 >= 12 }) {
            fail("page 2 shows \(page2)")
        }
        drawnHeld()
        guard let second = settled(texts()), second.evicted > 0 else { fail("page 1 not evicted: \(texts())") }
        if ImageStore.shared.bytes > 8 << 20 { fail("the store holds \(ImageStore.shared.bytes) bytes, over the budget") }
        let stats = SlowServer.stats
        if stats.most > 6 { fail("the server saw \(stats.most) requests at once") }
        engine.stop()
        print("selftest: PASS (Gallery: 3 pictures, 3 faults, reload, fit; grid reflows on resize; 24 thumbnails, at most \(stats.most) at once, \(afterCancel.stopped) stopped on Cancel; \(first.evicted) evicted under the budget, then \(second.evicted) after Next page)")
        print(String(format: "  launch to every tile answered: %.1f ms", loadMs))
    }
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

/// Resize the window's content to `size` as a drag does: the window's delegate (the host's
/// `WindowSizer`) sees the proposed frame first and may hold it at the minimum.
@MainActor
func drag(_ window: NSWindow, to size: NSSize) {
    var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    frame = window.delegate?.windowWillResize?(window, to: frame) ?? frame
    if frame == window.frame.size { return }
    let top = window.frame.maxY
    window.setFrame(NSRect(x: window.frame.minX, y: top - frame.height, width: frame.width, height: frame.height),
                    display: true)
}

/// Demo sweeps: after two seconds, drag the window through `legs` (content sizes, each leg's
/// seconds), a frame at a time, eased. Lean sees only the `resize` events.
func sweep(_ legs: [(NSSize, NSSize, Double)]) {
    let start = Date().addingTimeInterval(2)
    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        MainActor.assumeIsolated {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            var t = Date().timeIntervalSince(start)
            if t < 0 { drag(window, to: legs[0].0); return }
            for (a, b, leg) in legs {
                if t <= leg {
                    let u = t / leg, e = u * u * (3 - 2 * u)
                    drag(window, to: NSSize(width: (a.width + (b.width - a.width) * e).rounded(),
                                            height: (a.height + (b.height - a.height) * e).rounded()))
                    return
                }
                t -= leg
            }
            drag(window, to: legs[legs.count - 1].1)
        }
    }
}

/// `--demo-resize`: the width 1120 → 1640 → 1020 (the minimum) → 1120 at a height of 700.
if args.contains("--demo-resize") {
    func s(_ w: Double) -> NSSize { NSSize(width: w, height: 700) }
    sweep([(s(1120), s(1640), 3), (s(1640), s(1640), 1), (s(1640), s(1020), 4), (s(1020), s(1020), 1),
           (s(1020), s(1120), 2)])
}

/// `--demo-min-size`: from 1280 × 760, drag toward 760 × 420, well under the minimum (1020 ×
/// 536); the window stops at the minimum, with every tile 180 points wide, then goes back.
if args.contains("--demo-min-size") {
    let big = NSSize(width: 1280, height: 760), small = NSSize(width: 760, height: 420)
    let narrow = NSSize(width: 760, height: 760), short = NSSize(width: 1280, height: 420)
    sweep([(big, big, 1), (big, narrow, 3), (narrow, big, 2), (big, short, 3), (short, big, 2),
           (big, small, 3), (small, small, 1.5), (small, big, 2.5)])
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Gallery", size: size,
                                  makeWorld: { _ in World(handlers: .standard, devices: SlowServer.devices(.live)) }) {
        LeanCore(gallery)
    })
}
