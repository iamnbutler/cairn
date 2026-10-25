import CairnFrame
import CairnHost
import CairnRender
import CoreGraphics
import Foundation
import ImageIO

/// A URL protocol that answers image fetches from a script keyed by the URL's path.
final class ImageStubProtocol: URLProtocol, @unchecked Sendable {
    enum Answer { case respond(status: Int, body: Data), fail(Int) }
    static let answers = Locked<[String: Answer]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.answers.value[request.url?.path ?? ""] ?? .fail(NSURLErrorUnknown) {
        case let .respond(status, body):
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: code))
        }
    }
    override func stopLoading() {}
}

/// Images (docs/effects.md "Images", docs/frame.md `image` draws):
///
/// - `effects.load-image`: `loadImage` of a file or an http(s) URL holding a PNG, JPEG, TIFF,
///   GIF, BMP or HEIC (random size, sometimes over the 4096-pixel texture limit, with any EXIF
///   orientation) answers exactly once with the oriented pixel size and keeps the image for
///   draws; a missing file is `notFound`, an unreadable one `denied`, a directory, an empty
///   source, NUL, garbage or a truncated file `invalid`; HTTP 404/410 `notFound`, 401/403
///   `denied`, other statuses `other`, a failed connection `network`. Without `reload` a kept
///   source answers from the store without reading; with it the source is read again, and a
///   failure removes it.
/// - `render.image.bounds`: an `image` draw changes no pixel outside its box within the clip in
///   force, whatever its destination rect, and a draw naming a source the store doesn't hold
///   changes nothing (against the same frame without its image draws).
/// - `render.image.pixels`: drawn into its box, an image's four quadrants land where the
///   oriented image has them, in their colours.
final class ImageSuite: Suite {
    let name = "image"
    let crashCheck = "effects.load-image"
    let checks: [String: CheckInfo] = [
        "effects.load-image": CheckInfo(
            title: "`loadImage` answers the image's pixel size, or the fault",
            trusted: ["host/Sources/CairnHost/ImageEffects.swift", "host/Sources/CairnRender/Images.swift",
                      "ImageIO"],
            oracle: "images encoded here with ImageIO (their size and orientation), the file system's state and a URLProtocol stub"),
        "render.image.bounds": CheckInfo(
            title: "An image draw changes no pixel outside its box within the clip",
            trusted: ["host/Sources/CairnRender/Renderer.swift (image batches: scissor)", "Metal (scissor test)"],
            oracle: "the same frame rendered without its image draws, compared pixel by pixel"),
        "render.image.pixels": CheckInfo(
            title: "An image's pixels are drawn where the oriented image has them",
            trusted: ["host/Sources/CairnRender/Renderer.swift (image batches)", "host/Sources/CairnRender/Images.swift",
                      "ImageIO (orientation)"],
            oracle: "the quadrant colours encoded here, moved by the EXIF orientation's definition"),
    ]

    func cases(for n: Int) -> Int { max(10, n / 4) }

    var session: URLSession!
    nonisolated(unsafe) static var renderer: Renderer?

    func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [ImageStubProtocol.self]
        session = URLSession(configuration: c)
        if Self.renderer == nil { Self.renderer = try? Renderer() }
    }

    // MARK: Pictures

    static let palette: [(UInt8, UInt8, UInt8)] = [
        (230, 30, 30), (30, 200, 40), (30, 60, 230), (240, 220, 30), (20, 20, 20), (250, 250, 250),
        (220, 40, 220), (30, 210, 220),
    ]

    /// A stored image of four solid quadrants (top-left, top-right, bottom-left, bottom-right),
    /// encoded as `type` with EXIF `orientation`.
    struct Pic {
        var w, h: Int
        var quads: [(UInt8, UInt8, UInt8)]
        var type: String
        var orientation: Int
        var lossy: Bool { type == "public.jpeg" || type == "public.heic" }
        /// The displayed size: orientations 5–8 swap the sides.
        var shown: (Int, Int) { orientation >= 5 ? (h, w) : (w, h) }
        var description: String { "\(w)×\(h) \(type) orientation \(orientation) quadrants \(quads)" }
    }

    static func pic(_ g: inout SplitMix, big: Bool = true) -> Pic {
        let type = g.elem(["public.png", "public.png", "public.jpeg", "public.tiff", "com.compuserve.gif",
                           "com.microsoft.bmp", "public.heic"])
        let lossy = type == "public.jpeg" || type == "public.heic"
        let lo = lossy ? 64 : 4
        var w = g.range(lo, 220), h = g.range(lo, 220)
        if big, g.chance(1, 12) {
            // Over the texture limit on one side (kept thin, so encoding stays quick).
            if g.bool() { w = g.range(4097, 6000); h = lo } else { h = g.range(4097, 6000); w = lo }
        }
        var quads: [(UInt8, UInt8, UInt8)] = []
        var pool = palette
        for _ in 0..<4 { quads.append(pool.remove(at: g.below(pool.count))) }
        return Pic(w: w, h: h, quads: quads, type: type, orientation: g.range(1, 8))
    }

    static func encode(_ p: Pic) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: p.w, height: p.h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let hw = p.w / 2, hh = p.h / 2
        // Core Graphics is y up: the top rows are at high y.
        let rects = [CGRect(x: 0, y: hh, width: hw, height: p.h - hh), CGRect(x: hw, y: hh, width: p.w - hw, height: p.h - hh),
                     CGRect(x: 0, y: 0, width: hw, height: hh), CGRect(x: hw, y: 0, width: p.w - hw, height: hh)]
        for (q, r) in zip(p.quads, rects) {
            ctx.setFillColor(red: CGFloat(q.0) / 255, green: CGFloat(q.1) / 255, blue: CGFloat(q.2) / 255, alpha: 1)
            ctx.fill(r)
        }
        guard let img = ctx.makeImage() else { return nil }
        let d = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(d, p.type as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImagePropertyOrientation: p.orientation]
        if p.lossy { props[kCGImageDestinationLossyCompressionQuality] = 0.95 }
        CGImageDestinationAddImage(dst, img, props as CFDictionary)
        return CGImageDestinationFinalize(dst) ? d as Data : nil
    }

    /// The stored quadrant shown at displayed (u, v) in 0…1, by EXIF's definition of each
    /// orientation (displayed = transform(stored)).
    static func quadrant(_ p: Pic, _ u: Double, _ v: Double) -> (UInt8, UInt8, UInt8) {
        let (su, sv): (Double, Double) = switch p.orientation {
        case 2: (1 - u, v)
        case 3: (1 - u, 1 - v)
        case 4: (u, 1 - v)
        case 5: (v, u)
        case 6: (v, 1 - u)
        case 7: (1 - v, 1 - u)
        case 8: (1 - v, u)
        default: (u, v)
        }
        return p.quads[(sv < 0.5 ? 0 : 2) + (su < 0.5 ? 0 : 1)]
    }

    // MARK: Loading

    func load(_ source: String, reload: Bool, _ store: ImageStore) -> [Reply] {
        let got = Locked<[Reply]>([])
        let first = DispatchSemaphore(value: 0)
        ImageLoad.run(source: source, reload: reload, store: store, session: session) { rep in
            got.update { $0.append(rep) }
            first.signal()
        }
        _ = first.wait(timeout: .now() + 10)
        usleep(500)
        return got.value
    }

    func expectSize(_ r: Recorder, _ replies: [Reply], _ p: Pic, _ store: ImageStore, _ source: String, _ what: String) {
        let check = "effects.load-image"
        let (w, h) = p.shown
        guard r.expect(check, replies.count == 1, "\(replies.count) answers to \(what)") else { return }
        guard case let .image(rw, rh) = replies[0], Int(rw) == w, Int(rh) == h else {
            r.fail(check, "\(what) of \(p.description) answered \(replies[0]), expected image \(w) \(h)")
            return
        }
        guard let e = store.entry(source) else { r.fail(check, "\(what) answered but kept nothing"); return }
        r.expect(check, e.width == w && e.height == h, "kept \(e.width)×\(e.height), answered \(w)×\(h)")
        let long = max(e.pixels.width, e.pixels.height), want = min(max(w, h), ImageStore.maxSide)
        r.expect(check, abs(long - want) <= 1 && e.pixels.bytes.count == e.pixels.width * e.pixels.height * 4,
                 "pixels \(e.pixels.width)×\(e.pixels.height) for \(w)×\(h)")
        // Same orientation: the long side is the same side.
        r.expect(check, (w >= h) == (e.pixels.width >= e.pixels.height) || abs(w - h) <= 1 || min(e.pixels.width, e.pixels.height) <= 2,
                 "pixels \(e.pixels.width)×\(e.pixels.height) turned against \(w)×\(h)")
    }

    func expectFault(_ r: Recorder, _ replies: [Reply], _ f: Fault, _ what: String) {
        let check = "effects.load-image"
        guard r.expect(check, replies.count == 1, "\(replies.count) answers to \(what)") else { return }
        guard case let .failed(got, _) = replies[0], got == f else {
            r.fail(check, "\(what) answered \(replies[0]), expected failed \(f)")
            return
        }
        r.count(check, "\(f)")
    }

    func runLoad(_ g: inout SplitMix, _ r: Recorder) {
        let check = "effects.load-image"
        let store = ImageStore()
        let root = NSTemporaryDirectory() + "cairn-fuzz-image-\(getpid())-\(g.next())"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let p = Self.pic(&g)
        guard let data = Self.encode(p) else { r.fail(check, "could not encode \(p.description)"); return }
        let file = root + "/pic." + (p.type.split(separator: ".").last ?? "img")
        let url = "https://images.test/\(g.next())/pic"
        r.ran(check)
        switch g.below(10) {
        case 0, 1:
            try? data.write(to: URL(fileURLWithPath: file))
            expectSize(r, load(file, reload: g.bool(), store), p, store, file, "a file")
            r.count(check, "file \(p.type)")
            if max(p.w, p.h) > ImageStore.maxSide { r.count(check, "overLimit") }
        case 2:
            ImageStubProtocol.answers.update { $0[URL(string: url)!.path] = .respond(status: g.elem([200, 200, 201, 203]), body: data) }
            expectSize(r, load(url, reload: false, store), p, store, url, "a URL")
            r.count(check, "url")
        case 3:
            let (status, f): (Int, Fault) = g.elem([(404, .notFound), (410, .notFound), (401, .denied), (403, .denied),
                                                    (500, .other), (418, .other), (304, .other)])
            ImageStubProtocol.answers.update { $0[URL(string: url)!.path] = .respond(status: status, body: data) }
            expectFault(r, load(url, reload: g.bool(), store), f, "HTTP \(status)")
            r.expect(check, store.entry(url) == nil, "HTTP \(status) kept an image")
        case 4:
            ImageStubProtocol.answers.update {
                $0[URL(string: url)!.path] = g.bool() ? .fail(g.elem([NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet]))
                    : .respond(status: 200, body: Data(EventsSuite.bytes(&g).filter { _ in true }.prefix(40)) + Data("not an image".utf8))
            }
            let replies = load(url, reload: false, store)
            if case .fail = ImageStubProtocol.answers.value[URL(string: url)!.path]! {
                expectFault(r, replies, .network, "a failed connection")
            } else {
                expectFault(r, replies, .invalid, "a body that is no image")
            }
        case 5:
            switch g.below(5) {
            case 0: expectFault(r, load(root + "/missing.png", reload: g.bool(), store), .notFound, "a missing file")
            case 1: expectFault(r, load(root, reload: g.bool(), store), .invalid, "a directory")
            case 2:
                try? data.write(to: URL(fileURLWithPath: file))
                chmod(file, 0)
                if getuid() != 0 { expectFault(r, load(file, reload: false, store), .denied, "an unreadable file") }
                chmod(file, 0o600)
            case 3:
                let cut = g.bool() ? data.prefix(g.range(0, min(24, data.count))) : Data(EventsSuite.bytes(&g))
                try? cut.write(to: URL(fileURLWithPath: file))
                expectFault(r, load(file, reload: false, store), .invalid, "garbage or a truncated image")
            default:
                expectFault(r, load(g.bool() ? "" : root + "/a\u{0}b.png", reload: g.bool(), store), .invalid, "an empty or NUL source")
            }
            r.expect(check, store.count == 0, "a failed load kept an image")
        case 6, 7:
            // The store: without reload a kept source is answered without reading.
            try? data.write(to: URL(fileURLWithPath: file))
            expectSize(r, load(file, reload: false, store), p, store, file, "a first load")
            let q = Self.pic(&g, big: false)
            if g.bool() {
                try? FileManager.default.removeItem(atPath: file)
                expectSize(r, load(file, reload: false, store), p, store, file, "a load of a kept, deleted file")
                expectFault(r, load(file, reload: true, store), .notFound, "a reload of a deleted file")
                r.expect(check, store.entry(file) == nil, "a failed reload left the image kept")
                r.count(check, "reloadRemoves")
            } else if let qd = Self.encode(q) {
                let before = store.entry(file)?.generation ?? -1
                try? qd.write(to: URL(fileURLWithPath: file))
                expectSize(r, load(file, reload: false, store), p, store, file, "a load of a kept, replaced file")
                expectSize(r, load(file, reload: true, store), q, store, file, "a reload of a replaced file")
                r.expect(check, (store.entry(file)?.generation ?? -1) > before, "a reload kept the old generation")
                r.count(check, "reloadReplaces")
            }
        default:
            // Many loads at once, each answered once with its own size.
            let pics = (0..<g.range(2, 6)).map { _ in Self.pic(&g, big: false) }
            let paths = pics.indices.map { root + "/p\($0)" }
            for (pp, path) in zip(pics, paths) { if let d = Self.encode(pp) { try? d.write(to: URL(fileURLWithPath: path)) } }
            let results = Locked<[Int: [Reply]]>([:])
            DispatchQueue.concurrentPerform(iterations: pics.count) { i in
                let rs = load(paths[i], reload: true, store)
                results.update { $0[i] = rs }
            }
            for i in pics.indices { expectSize(r, results.value[i] ?? [], pics[i], store, paths[i], "concurrent load \(i)") }
            r.count(check, "concurrent")
        }
    }

    // MARK: Rendering

    func runPixels(_ g: inout SplitMix, _ r: Recorder) {
        let check = "render.image.pixels"
        guard let renderer = Self.renderer else { r.fail(check, "no Metal device"); return }
        var p = Self.pic(&g, big: false)
        if !p.lossy, g.chance(1, 3) { p.w = g.range(4, 12); p.h = g.range(4, 12) }  // magnified
        guard let data = Self.encode(p), let d = ImageStore.decode(data) else { r.fail(check, "could not decode \(p.description)"); return }
        let store = ImageStore()
        store.put("pic", d)
        renderer.images = store
        defer { renderer.images = .shared }
        let scale: Float = g.elem([1, 1.5, 2, 3])
        // Each quadrant at least 8 device pixels.
        let minSide = Int((16 / scale).rounded(.up))
        let bw = g.range(minSide, 160), bh = g.range(minSide, 160)
        let m = g.range(0, 12)
        let box = Rect(x: Int32(m), y: Int32(m), w: Int32(bw), h: Int32(bh))
        let frame = Frame(size: Size(w: Int32(bw + 2 * m), h: Int32(bh + 2 * m)),
                          draws: [.rect(Rect(x: 0, y: 0, w: Int32(bw + 2 * m), h: Int32(bh + 2 * m)),
                                        fill: Color(r: 128, g: 128, b: 128), radius: 0, border: nil),
                                  .image(box, dest: box, source: "pic")])
        do {
            let img = try renderer.image(frame, scale: scale)
            r.ran(check)
            let tol = p.lossy ? 40 : 8
            for (u, v) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
                let x = Int(((Double(m) + Double(bw) * u) * Double(scale)).rounded(.down))
                let y = Int(((Double(m) + Double(bh) * v) * Double(scale)).rounded(.down))
                let c = img.pixel(min(x, img.width - 1), min(y, img.height - 1))
                let want = Self.quadrant(p, u, v)
                let ok = abs(Int(c.r) - Int(want.0)) <= tol && abs(Int(c.g) - Int(want.1)) <= tol
                    && abs(Int(c.b) - Int(want.2)) <= tol && c.a == 255
                if !ok {
                    r.fail(check, "at (\(u), \(v)) of \(p.description) in box \(bw)×\(bh) at scale \(scale): \(c), expected \(want)")
                    return
                }
            }
            r.count(check, "orientation \(p.orientation)")
            r.count(check, p.type)
        } catch {
            r.fail(check, "render failed: \(error)")
        }
    }

    func runBounds(_ g: inout SplitMix, _ r: Recorder) {
        let check = "render.image.bounds"
        guard let renderer = Self.renderer else { r.fail(check, "no Metal device"); return }
        let store = ImageStore()
        let sources = ["a", "b", "c"]
        for s in sources {
            var p = Self.pic(&g, big: false)
            p.type = "public.png"; p.w = g.range(1, 64); p.h = g.range(1, 64)
            if let d = Self.encode(p).flatMap(ImageStore.decode) { store.put(s, d) }
        }
        renderer.images = store
        defer { renderer.images = .shared }
        let scale: Float = g.elem([1, 1.5, 2, 2, 3])
        let w = Int32(g.range(1, 160)), h = Int32(g.range(1, 120))
        var draws: [Draw] = []
        var depth = 0
        for _ in 0..<g.range(1, 8) {
            switch g.below(6) {
            case 0, 1:
                draws.append(.rect(PaintSuite.rect(&g, w, h), fill: Color(r: UInt8(g.below(256)), g: UInt8(g.below(256)),
                                                                          b: UInt8(g.below(256)), a: UInt8(g.below(256))),
                                   radius: UInt32(g.below(10)), border: nil))
            case 2: draws.append(.pushClip(PaintSuite.rect(&g, w, h))); depth += 1
            case 3 where depth > 0: draws.append(.popClip); depth -= 1
            default:
                draws.append(.image(PaintSuite.rect(&g, w, h), dest: PaintSuite.rect(&g, w, h),
                                    source: g.weighted([(6, { $0.elem(sources) }), (1, { _ in "missing" })])))
            }
        }
        if !draws.contains(where: { if case .image = $0 { true } else { false } }) {
            draws.insert(.image(PaintSuite.rect(&g, w, h), dest: PaintSuite.rect(&g, w, h), source: g.elem(sources)),
                         at: g.range(0, draws.count))
        }
        let frame = Frame(size: Size(w: w, h: h), draws: draws)
        let pw = Int((Float(w) * scale).rounded(.up)), ph = Int((Float(h) * scale).rounded(.up))
        var clips = [PaintSuite.Box(x0: 0, y0: 0, x1: max(1, pw), y1: max(1, ph))]
        var allowed: [PaintSuite.Box] = []
        var without: [Draw] = []
        for d in draws {
            switch d {
            case let .pushClip(rc): clips.append(clips.last!.meet(PaintSuite.covering(rc, scale))); without.append(d)
            case .popClip: if clips.count > 1 { clips.removeLast() }; without.append(d)
            case let .image(rc, _, src):
                // A missing source may change nothing at all.
                if store.entry(src) != nil { allowed.append(clips.last!.meet(PaintSuite.covering(rc, scale))) }
                r.count(check, src == "missing" ? "missing" : "loaded")
            default: without.append(d)
            }
        }
        var bare = frame
        bare.draws = without
        do {
            let a = try renderer.image(frame, scale: scale)
            let b = try renderer.image(bare, scale: scale)
            r.ran(check)
            var inside = 0
            for y in 0..<a.height {
                for x in 0..<a.width {
                    let i = (y * a.width + x) * 4
                    guard a.bgra[i..<(i + 4)] != b.bgra[i..<(i + 4)] else { continue }
                    if allowed.contains(where: { $0.contains(x, y) }) { inside += 1; continue }
                    r.fail(check, "pixel (\(x), \(y)) changed outside every image box \(allowed)",
                           repro: { "scale \(scale)\n" + Dump.canvas(frame.window) })
                    return
                }
            }
            r.count(check, inside > 0 ? "paintedInside" : "nothingPainted")
        } catch {
            r.fail(check, "render failed: \(error)")
        }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        switch g.below(4) {
        case 0, 1: runLoad(&g, r)
        case 2: runPixels(&g, r)
        default: runBounds(&g, r)
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "loadImage, image pixels or image bounds (case kind \(g.below(4)))"
    }
}
