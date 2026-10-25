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
//
// The app names its bundled pictures by paths relative to its resources (`images/…`), so the
// host starts there.

let gallery = LeanApp(
    module: runtime_initialize_cairn_Examples_Gallery_Abi,
    initialize: { w, h, scale in cairn_app_init(w, h, scale) },
    step: { cairn_app_step($0, $1) },
    frame: { cairn_app_frame($0) },
    codec: FrameV1Codec())

let size = Size(w: 720, h: 560)
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

@MainActor
enum SelfTest {
    static func run() {
        // Inert devices: the https tile fails without touching the network.
        let engine = Engine(size: size, scalePercent: 200, world: World(handlers: .standard, devices: .inert)) {
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
        if !drawn.allSatisfy({ $0.0.w == 200 && $0.0.h == 150 }) { fail("image boxes \(drawn)") }
        for src in ["images/ridge.png", "images/tide.jpg", "images/moss.gif"] {
            guard let e = ImageStore.shared.entry(src) else { fail("\(src) not kept") }
            if src == "images/tide.jpg", (e.pixels.width, e.pixels.height) != (480, 320) { fail("tide not turned: \(e.pixels.width)×\(e.pixels.height)") }
        }

        // Reload: every source again, past the cache; the same answers come back.
        click("^501")
        until("reloaded") {
            $0.contains("Reloads: 1") && $0.filter { $0 == "480 × 320 px" }.count == 2 && $0.contains("Not found")
        }
        // Fit cycles; the boxes stay 200 × 150.
        click("^502")
        until("contain") { $0.contains("Fit: Contain") }
        if !images().allSatisfy({ $0.0.w == 200 && $0.0.h == 150 }) { fail("boxes moved on Fit: \(images())") }
        if count("Offline") != 1 { fail("the URL tile: \(texts())") }
        engine.stop()
        print("selftest: PASS (Gallery: 3 pictures, 3 faults, reload, fit; boxes fixed)")
        print(String(format: "  launch to every tile answered: %.1f ms", loadMs))
    }
}

/// Draws nothing; for the headless self test.
final class NullRenderer: FrameRenderer {
    let device = MTLCreateSystemDefaultDevice()!
    func configure(_ layer: CAMetalLayer) { layer.device = device }
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport) {}
}

MainActor.assumeIsolated {
    CairnApp.main(CairnApp.Config(title: "Gallery", size: size) { LeanCore(gallery) })
}
