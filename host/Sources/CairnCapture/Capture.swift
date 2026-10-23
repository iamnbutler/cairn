import CairnFrame
import CairnHost
import CairnRender
import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Headless screenshots for the map (tools/map, docs/map.md).
///
/// Runs an app's real `step` and `frame` on a Lean thread, replays scripted sequences of
/// actions as pointer events at each control's centre (found in the frame's accessibility
/// nodes), renders every frame offscreen with `Renderer.image(_:scale:)`, and writes each
/// image twice: plain, and with a pin on every control's rect labelled `^N` or `^N#k`. No window,
/// no screen capture.
///
/// An app opts in with one line in its executable (each executable links exactly one app):
///
///     if let code = MapCapture.main(CommandLine.arguments, size: size, core: { LeanCore(app) }) { exit(code) }
///
/// and is then run as `<App> --map-capture <script.json> <out dir>`.
public enum MapCapture {
    /// The script tools/map writes: sequences of actions from the initial state.
    struct Script: Decodable {
        var scale: Float?
        var sequences: [Sequence]
    }
    struct Sequence: Decodable {
        var name: String
        var steps: [Step]
    }
    struct Step: Codable {
        var trigger: String
        var claim: UInt32
        var key: UInt32
    }

    struct Control: Encodable {
        var ref: String, claim: UInt32, key: UInt32
        var role: String, label: String
        var rect: [Int32]
    }
    struct Shot: Encodable {
        /// The index of the step this frame follows; nil for the initial frame.
        var after: Int?
        var image: String, pinned: String
        var width: Int, height: Int
        var controls: [Control]
    }
    struct StepResult: Encodable {
        var step: Step
        var ref: String
        /// `ok`, `absent` (no control with that ref in the frame), `unsupported` (a trigger the
        /// capture can't perform yet) or `inert` (performed, and the frame did not change).
        var outcome: String
        var at: [Int32]?
    }
    struct SequenceResult: Encodable {
        var name: String
        var shots: [Shot]
        var steps: [StepResult]
    }
    struct Output: Encodable {
        var size: [Int32], scale: Float
        var sequences: [SequenceResult]
    }

    /// Runs the capture if `args` asks for it, and returns the exit code; nil otherwise.
    public static func main(_ args: [String], size: Size, core: @escaping () -> AppCore) -> Int32? {
        guard let i = args.firstIndex(of: "--map-capture") else { return nil }
        guard i + 2 < args.count else {
            FileHandle.standardError.write("usage: --map-capture <script.json> <out dir>\n".data(using: .utf8)!)
            return 2
        }
        do {
            let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: URL(fileURLWithPath: args[i + 1])))
            try run(script, size: size, core: core, out: URL(fileURLWithPath: args[i + 2], isDirectory: true))
            return 0
        } catch {
            FileHandle.standardError.write("map capture: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }

    static func run(_ script: Script, size: Size, core: @escaping () -> AppCore, out: URL) throws {
        let scale = script.scale ?? 2
        let renderer = try Renderer()
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Each sequence starts from a fresh app. Lean runs on its own thread with a large stack,
        // as in the host (AGENTS.md); frames come back here to be rendered.
        var results: [SequenceResult] = []
        for seq in script.sequences {
            let frames = try onLeanThread { () throws -> ([Frame], [StepResult]) in
                let app = core()
                app.start(size: size, scalePercent: UInt32(scale * 100))
                var frames = [try app.frame()]
                var steps: [StepResult] = []
                for step in seq.steps {
                    let ref = ControlRef(claim: step.claim, key: step.key)
                    let current = frames.last!
                    guard let node = current.ax.first(where: { $0.control == ref }) else {
                        steps.append(StepResult(step: step, ref: ref.label, outcome: "absent", at: nil))
                        break
                    }
                    let c = Point(x: node.rect.x + node.rect.w / 2, y: node.rect.y + node.rect.h / 2)
                    let click: (UInt32) -> [Event] = { n in
                        [.pointerDown(c, .primary, clicks: n, Mods()), .pointerUp(c, .primary, Mods())]
                    }
                    let events: [Event]? = switch step.trigger {
                    case "press": [.pointerMove(c)] + click(1)
                    case "doublePress": [.pointerMove(c)] + click(1) + click(2)
                    default: nil  // edit, submit, cancel, blur: need focus and keys; not yet
                    }
                    guard let events else {
                        steps.append(StepResult(step: step, ref: ref.label, outcome: "unsupported", at: [c.x, c.y]))
                        break
                    }
                    app.step(events)
                    let next = try app.frame()
                    frames.append(next)
                    steps.append(StepResult(step: step, ref: ref.label, outcome: next == current ? "inert" : "ok", at: [c.x, c.y]))
                }
                return (frames, steps)
            }
            var shots: [Shot] = []
            for (k, frame) in frames.0.enumerated() {
                let base = "\(seq.name)-\(k)"
                let img = try renderer.image(frame, scale: scale)
                let controls = frame.ax.compactMap { n -> Control? in
                    guard let c = n.control else { return nil }
                    return Control(ref: c.label, claim: c.claim, key: c.key, role: "\(n.role)", label: n.label,
                                   rect: [n.rect.x, n.rect.y, n.rect.w, n.rect.h])
                }
                // The control the next step acts on is drawn as the active pin.
                let next = k < frames.1.count ? frames.1[k].ref : nil
                let plain = opaque(img.cgImage())
                try write(plain, to: out.appendingPathComponent("\(base).png"))
                try write(pinned(plain, frame: frame, scale: CGFloat(scale), active: next),
                          to: out.appendingPathComponent("\(base).pinned.png"))
                shots.append(Shot(after: k == 0 ? nil : k - 1, image: "\(base).png", pinned: "\(base).pinned.png",
                                  width: img.width, height: img.height, controls: controls))
            }
            results.append(SequenceResult(name: seq.name, shots: shots, steps: frames.1))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(Output(size: [size.w, size.h], scale: scale, sequences: results))
            .write(to: out.appendingPathComponent("capture.json"))
    }

    /// Runs `body` on a fresh thread with a 64 MB stack (Lean recursion on deep trees) and waits.
    static func onLeanThread<T>(_ body: @escaping () throws -> T) throws -> T {
        nonisolated(unsafe) var result: Result<T, Error>?
        let done = DispatchSemaphore(value: 0)
        let t = Thread {
            result = Result { try body() }
            done.signal()
        }
        t.stackSize = 64 << 20
        t.start()
        done.wait()
        return try result!.get()
    }

    // MARK: Images

    static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    }

    /// The frame over white: a window's content has a background; the renderer's target doesn't.
    static func opaque(_ img: CGImage) -> CGImage {
        let ctx = context(img.width, img.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()!
    }

    /// Pins: each control's rect outlined, with its ref in a badge at the top-left corner. Rects
    /// come from the frame's accessibility nodes (the visible rect: the node's rect intersected
    /// with its clip), so a pin is where layout put the control, never placed by hand.
    static func pinned(_ img: CGImage, frame: Frame, scale s: CGFloat, active: String?) -> CGImage {
        let w = img.width, h = img.height
        let ctx = context(w, h)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Logical points, y down, as the frame is.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: s, y: -s)
        let ink = CGColor(red: 0.85, green: 0.27, blue: 0.05, alpha: 1)   // pins
        let hot = CGColor(red: 0.10, green: 0.35, blue: 0.95, alpha: 1)   // the next step's control
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 11, nil)!
        for node in frame.ax {
            guard let c = node.control else { continue }
            let color = c.label == active ? hot : ink
            let r = CGRect(x: CGFloat(node.rect.x), y: CGFloat(node.rect.y), width: CGFloat(node.rect.w), height: CGFloat(node.rect.h))
            ctx.setStrokeColor(color)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: c.label == active ? [] : [4, 3])
            ctx.stroke(r.insetBy(dx: -2, dy: -2))
            // Badge: the ref, white on the pin colour, sitting on the rect's top-left corner.
            let text = NSAttributedString(string: c.label, attributes: [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)])
            let line = CTLineCreateWithAttributedString(text)
            let tw = CTLineGetTypographicBounds(line, nil, nil, nil)
            let badge = CGRect(x: max(0, r.minX - 3), y: max(0, r.minY - 16), width: CGFloat(tw) + 10, height: 15)
            ctx.setFillColor(color)
            ctx.addPath(CGPath(roundedRect: badge, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()
            ctx.saveGState()
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: badge.minX + 5, y: badge.maxY - 4)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        return ctx.makeImage()!
    }

    static func write(_ img: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
