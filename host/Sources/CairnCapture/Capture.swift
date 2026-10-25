import CairnFrame
import CairnHost
import CairnRender
import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Headless screenshots of an app (`make capture`, docs/claim-pages.md).
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
    /// The script tools/map/capture-script.ts writes: sequences of actions from the initial state.
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
        /// An edit's text operation: `{"kind": "insert", "text": "milk"}`.
        var op: Op?
    }
    struct Op: Codable {
        var kind: String
        var text: String?
    }
    /// A step without its control: what the try capture's actions are made of.
    struct Gesture: Codable {
        var trigger: String
        var op: Op?
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
        /// The pinned frames side by side.
        var strip: String
    }
    struct Output: Encodable {
        var size: [Int32], scale: Float
        /// The logical rect of the window every image shows (x, y, w, h).
        var crop: [Int32]
        var sequences: [SequenceResult]
    }

    /// Runs the capture if `args` asks for it, and returns the exit code; nil otherwise.
    /// Also runs the try capture (`--try-capture`, Explore.swift), so every app that opts in here
    /// gets both.
    public static func main(_ args: [String], size: Size, core: @escaping () -> AppCore) -> Int32? {
        if let code = TryCapture.main(args, size: size, core: core) { return code }
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
        var runs: [(seq: Sequence, frames: [Frame], steps: [StepResult])] = []
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
                    guard let events = events(trigger: step.trigger, op: step.op, node: node, frame: current) else {
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
            runs.append((seq, frames.0, frames.1))
        }

        // Render everything, then crop every image to one rect: the union of what was painted
        // and the pins (badges sit above and left of their rect), padded, inside the window. One
        // crop for the whole capture keeps every image the same size and the same place.
        var images: [[Image]] = []
        var ink: CGRect = .null
        for run in runs {
            var row: [Image] = []
            for frame in run.frames {
                let img = try renderer.image(frame, scale: scale)
                ink = ink.union(inkBounds(img, scale: CGFloat(scale)))
                for n in frame.ax where n.control != nil {
                    ink = ink.union(CGRect(x: CGFloat(n.rect.x) - 5, y: CGFloat(n.rect.y) - 18,
                                           width: CGFloat(n.rect.w) + 10, height: CGFloat(n.rect.h) + 22))
                }
                row.append(img)
            }
            images.append(row)
        }
        let window = CGRect(x: 0, y: 0, width: CGFloat(size.w), height: CGFloat(size.h))
        let crop = ink.isNull ? window : ink.insetBy(dx: -16, dy: -16).integral.intersection(window)
        let px = CGRect(x: crop.minX * CGFloat(scale), y: crop.minY * CGFloat(scale),
                        width: crop.width * CGFloat(scale), height: crop.height * CGFloat(scale)).integral

        var results: [SequenceResult] = []
        for (r, run) in runs.enumerated() {
            var shots: [Shot] = []
            var stripFrames: [CGImage] = []
            for (k, frame) in run.frames.enumerated() {
                let base = "\(run.seq.name)-\(k)"
                let controls = frame.ax.compactMap { n -> Control? in
                    guard let c = n.control else { return nil }
                    return Control(ref: c.label, claim: c.claim, key: c.key, role: "\(n.role)", label: n.label,
                                   rect: [n.rect.x, n.rect.y, n.rect.w, n.rect.h])
                }
                // The control the next step acts on is drawn as the active pin.
                let next = k < run.steps.count ? run.steps[k].ref : nil
                let plain = opaque(images[r][k].cgImage())
                let pins = pinned(plain, frame: frame, scale: CGFloat(scale), active: next)
                try write(plain.cropping(to: px)!, to: out.appendingPathComponent("\(base).png"))
                try write(pins.cropping(to: px)!, to: out.appendingPathComponent("\(base).pinned.png"))
                stripFrames.append(pins.cropping(to: px)!)
                shots.append(Shot(after: k == 0 ? nil : k - 1, image: "\(base).png", pinned: "\(base).pinned.png",
                                  width: Int(px.width), height: Int(px.height), controls: controls))
            }
            let labels = ["Start"] + run.steps.prefix(stripFrames.count - 1).enumerated().map { "\($0.offset + 1). \($0.element.step.trigger) \($0.element.ref)" }
            try write(strip(stripFrames, labels: labels, scale: CGFloat(scale)), to: out.appendingPathComponent("\(run.seq.name).strip.png"))
            results.append(SequenceResult(name: run.seq.name, shots: shots, steps: run.steps, strip: "\(run.seq.name).strip.png"))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(Output(size: [size.w, size.h], scale: scale,
                              crop: [Int32(crop.minX), Int32(crop.minY), Int32(crop.width), Int32(crop.height)],
                              sequences: results))
            .write(to: out.appendingPathComponent("capture.json"))
    }


    /// The events a person's step on `node` sends: pointer events at its centre, or, for a text
    /// step, a click to focus the field unless it has focus, then the text or key. nil for a
    /// trigger the capture can't send yet (blur and the rarer text operations).
    static func events(trigger: String, op: Op?, node: AxNode, frame: Frame) -> [Event]? {
        let c = Point(x: node.rect.x + node.rect.w / 2, y: node.rect.y + node.rect.h / 2)
        let click: (UInt32) -> [Event] = { n in
            [.pointerDown(c, .primary, clicks: n, Mods()), .pointerUp(c, .primary, Mods())]
        }
        let focus = node.control != nil && frame.textInput?.control == node.control ? [] : [.pointerMove(c)] + click(1)
        return switch (trigger, op?.kind) {
        case ("press", _): [.pointerMove(c)] + click(1)
        case ("doublePress", _): [.pointerMove(c)] + click(1) + click(2)
        case ("edit", "insert"): focus + [.insertText(op?.text ?? "")]
        case ("edit", "paste"): focus + [.paste(op?.text ?? "")]
        case ("edit", "deleteBackward"): focus + [.key(.backspace, Mods())]
        case ("edit", "deleteForward"): focus + [.key(.delete, Mods())]
        case ("edit", "selectAll"): focus + [.selectAll]
        case ("edit", "undo"): focus + [.undo]
        case ("edit", "redo"): focus + [.redo]
        case ("submit", _): focus + [.key(.enter, Mods())]
        case ("cancel", _): focus + [.key(.escape, Mods())]
        default: nil
        }
    }

    /// A sequence's pinned frames in reading order, each labelled with the step that led to it, so a
    /// flow reads left to right in one image.
    static func strip(_ frames: [CGImage], labels: [String], scale s: CGFloat) -> CGImage {
        // Every frame has the same size (one crop). Up to four in a row; longer runs wrap at three.
        let fw = frames.map(\.width).max() ?? 1, fh = frames.map(\.height).max() ?? 1
        let cols = frames.count <= 4 ? max(1, frames.count) : 3
        let rows = (frames.count + cols - 1) / cols
        let gap = Int(28 * s), labelH = Int(26 * s), rowGap = Int(12 * s)
        let w = cols * fw + (cols - 1) * gap
        let h = rows * (fh + labelH) + (rows - 1) * rowGap
        let ctx = context(w, h)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateUIFontForLanguage(.system, 12 * s, nil)!
        let grey = CGColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1)
        for (k, img) in frames.enumerated() {
            let x = (k % cols) * (fw + gap)
            let top = (k / cols) * (fh + labelH + rowGap)          // from the top, y down
            let frameRect = CGRect(x: x, y: h - top - img.height, width: img.width, height: img.height)
            ctx.draw(img, in: frameRect)
            ctx.setStrokeColor(CGColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1))
            ctx.setLineWidth(s)
            ctx.stroke(frameRect.insetBy(dx: s / 2, dy: s / 2))
            let text = NSAttributedString(string: labels[k], attributes: [
                .init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): grey])
            ctx.textPosition = CGPoint(x: CGFloat(x) + 4 * s, y: frameRect.minY - CGFloat(labelH) + 8 * s)
            CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
            if k + 1 < frames.count && (k + 1) % cols != 0 {
                // An arrow in the gap to the next frame in the row.
                let y = frameRect.midY, x0 = frameRect.maxX + 7 * s, x1 = frameRect.maxX + CGFloat(gap) - 7 * s
                ctx.setStrokeColor(grey)
                ctx.setLineWidth(1.5 * s)
                ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y))
                ctx.move(to: CGPoint(x: x1 - 5 * s, y: y + 4 * s)); ctx.addLine(to: CGPoint(x: x1, y: y)); ctx.addLine(to: CGPoint(x: x1 - 5 * s, y: y - 4 * s))
                ctx.strokePath()
            }
        }
        return ctx.makeImage()!
    }

    /// The logical rect holding every pixel that differs from the background (the renderer's
    /// clear colour, read from the top-left pixel).
    static func inkBounds(_ img: Image, scale: CGFloat) -> CGRect {
        // One pixel as one UInt32: the scan runs on every frame of a try capture (hundreds), so
        // it reads the buffer directly rather than comparing slices.
        var minX = img.width, minY = img.height, maxX = -1, maxY = -1
        img.bgra.withUnsafeBytes { raw in
            let px = raw.bindMemory(to: UInt32.self)
            guard let base = px.baseAddress, px.count > 0 else { return }
            let bg = base[0], w = img.width, h = img.height
            // while loops: a debug build doesn't specialize Range iteration, and is 10× slower.
            var y = 0
            while y < h {
                let row = base + y * w
                var x = 0
                while x < w {
                    if row[x] != bg {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        maxY = y
                    }
                    x += 1
                }
                y += 1
            }
        }
        guard maxX >= 0 else { return .null }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
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
