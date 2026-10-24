import AppKit
import CairnFrame
import CairnHost
import CairnRender
import CoreGraphics
import CoreText
import Foundation

/// Headless screenshots for the map of an app whose surfaces are a status item and panels
/// (docs/map.md, "Surfaces"). The app drives its own capture, since its states come from its
/// world (Yap: a fake key and microphone), and hands each frame here to be drawn:
///
/// - the **status item** and its **menu**, drawn by the capture from the `NSMenu` the host built
///   from the frame (`MenuHost`): titles, enabled and greyed items, checkmarks, shortcuts and
///   status lines, submenus cascaded open. AppKit draws a real menu in another process, so this
///   is not a screenshot of it; it is what the host's menu holds;
/// - each shown **panel**, rendered offscreen by the renderer from its canvas, as the app's
///   panel draws it.
///
/// No window, no screen capture. Pins go on the status item's button and on every enabled menu
/// item, labelled with its ref; greyed items are drawn grey and not pinned (a person can't act
/// on them).
public enum SurfaceCapture {
    /// One step of the map's capture script (tools/map/cairn-map.ts `script`).
    public struct Step: Sendable {
        public let trigger: String
        public let claim: UInt32
        public let key: UInt32
        public init(trigger: String, claim: UInt32, key: UInt32) { self.trigger = trigger; self.claim = claim; self.key = key }
        public var ref: ControlRef { ControlRef(claim: claim, key: key) }
    }
    public struct Sequence: Sendable {
        public let name: String
        public let steps: [Step]
        public init(name: String, steps: [Step]) { self.name = name; self.steps = steps }
    }

    /// The script at `path`: its scale and sequences.
    public static func script(at path: String) throws -> (scale: Float, sequences: [Sequence]) {
        let s = try JSONDecoder().decode(MapCapture.Script.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return (s.scale ?? 2, s.sequences.map { q in
            Sequence(name: q.name, steps: q.steps.map { Step(trigger: $0.trigger, claim: $0.claim, key: $0.key) })
        })
    }

    /// A control drawn in a shot, in the shot's logical coordinates (y down).
    public struct Pin: Sendable {
        public var ref: ControlRef
        public var role: String
        public var label: String
        public var rect: CGRect
    }

    /// One drawn frame.
    public struct Shot: @unchecked Sendable {
        public var image: CGImage
        public var size: CGSize
        public var pins: [Pin]
        public var places: [UInt32]
    }

    /// What became of a step: `ok`, `inert` (performed; the frame didn't change), `absent` (no
    /// such control) or `unsupported`.
    public struct Outcome: Sendable {
        public var step: Step
        public var outcome: String
        public init(_ step: Step, _ outcome: String) { self.step = step; self.outcome = outcome }
    }

    // MARK: Drawing

    static let pad: CGFloat = 16
    /// Room above the menu bar for the status item's pin.
    static let top: CGFloat = 18
    static let barH: CGFloat = 24
    /// Rows are taller than AppKit's (22) so each pin's badge sits above its row, not on the
    /// text of the one before.
    static let rowH: CGFloat = 38
    static let pinH: CGFloat = 24
    static let sepH: CGFloat = 11
    static let menuInset: CGFloat = 5

    /// Draws a frame's shown status items (button and menu) and panels. `panel` renders a
    /// panel's canvas (the renderer, offscreen) at `scale`.
    @MainActor
    public static func draw(_ frame: Frame, menu: (UInt32) -> NSMenu?, scale: CGFloat,
                            panel: (Surface) throws -> CGImage) rethrows -> Shot {
        // Lay out first (logical points, y down), then paint.
        var paints: [(CGContext) -> Void] = []
        var pins: [Pin] = []
        var places: [UInt32] = []
        var right: CGFloat = 0, bottom: CGFloat = top + barH
        var x = pad

        for s in frame.surfaces where s.kind == .statusItem && s.shown {
            places.append(s.place)
            let st = s.status
            let title = st.title
            let tw = title.isEmpty ? 0 : textWidth(title, font: menuFont) + 4
            let button = CGRect(x: x, y: top + 2, width: 16 + 14 + tw, height: barH - 4)
            paints.append { ctx in
                fill(ctx, button, gray(0.82), radius: 4)
                if let img = symbol(st.symbol, scale: scale) {
                    ctx.draw(img, in: CGRect(x: button.minX + 7, y: button.minY + 2, width: 16, height: 16), byTiling: false)
                }
                if !title.isEmpty { text(ctx, title, at: CGPoint(x: button.minX + 27, y: button.midY), font: menuFont, color: gray(0)) }
            }
            pins.append(Pin(ref: st.control, role: "statusItem", label: st.label, rect: button))
            if let root = menu(s.place) {
                let (r, b) = layoutMenu(root, origin: CGPoint(x: x, y: top + barH + 2), paints: &paints, pins: &pins)
                right = max(right, r)
                bottom = max(bottom, b)
            }
            x = max(x + button.width + 24, right + 24)
            right = max(right, button.maxX)
        }

        var panelTop = bottom + 28
        for s in frame.surfaces where s.kind == .panel && s.shown {
            places.append(s.place)
            let img = try panel(s)
            let r = CGRect(x: pad, y: panelTop, width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
            paints.append { ctx in
                ctx.saveGState()
                ctx.translateBy(x: r.minX, y: r.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
                ctx.restoreGState()
            }
            right = max(right, r.maxX)
            panelTop = r.maxY + 16
            bottom = max(bottom, r.maxY)
        }

        let size = CGSize(width: ceil(right + pad), height: ceil(bottom + pad))
        let ctx = MapCapture.context(Int(size.width * scale), Int(size.height * scale))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        ctx.translateBy(x: 0, y: CGFloat(ctx.height))
        ctx.scaleBy(x: scale, y: -scale)
        // The menu bar.
        ctx.setFillColor(gray(0.93))
        ctx.fill(CGRect(x: 0, y: top, width: size.width, height: barH))
        ctx.setFillColor(gray(0.8))
        ctx.fill(CGRect(x: 0, y: top + barH - 0.5, width: size.width, height: 0.5))
        for p in paints { p(ctx) }
        return Shot(image: ctx.makeImage()!, size: size, pins: pins, places: places)
    }

    /// Lays out `menu` at `origin` (its top-left), and its submenus cascaded to the right of
    /// their items. Returns the rightmost and lowest points drawn.
    @MainActor
    static func layoutMenu(_ menu: NSMenu, origin: CGPoint, paints: inout [(CGContext) -> Void],
                           pins: inout [Pin]) -> (CGFloat, CGFloat) {
        let items = menu.items
        let check: CGFloat = 22, gap: CGFloat = 28, inset: CGFloat = 14
        let textW = items.map { $0.isSeparatorItem ? 0 : textWidth($0.title, font: menuFont) }.max() ?? 0
        let tailW = items.map { item -> CGFloat in
            if item.submenu != nil { return 10 }
            let k = shortcut(item)
            return k.isEmpty ? 0 : textWidth(k, font: menuFont)
        }.max() ?? 0
        let width = max(180, check + textW + gap + tailW + inset)
        var y = origin.y + menuInset
        var rows: [(NSMenuItem, CGRect)] = []
        for item in items {
            let h = item.isSeparatorItem ? sepH : rowH
            rows.append((item, CGRect(x: origin.x, y: y, width: width, height: h)))
            y += h
        }
        let box = CGRect(x: origin.x, y: origin.y, width: width, height: y + menuInset - origin.y)
        var right = box.maxX, bottom = box.maxY
        paints.append { ctx in
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
            fill(ctx, box, gray(0.985), radius: 7)
            ctx.restoreGState()
            ctx.setStrokeColor(gray(0.78))
            ctx.setLineWidth(0.5)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 7, cornerHeight: 7, transform: nil))
            ctx.strokePath()
        }
        for (item, r) in rows {
            if item.isSeparatorItem {
                paints.append { ctx in
                    ctx.setFillColor(gray(0.85))
                    ctx.fill(CGRect(x: r.minX + 10, y: r.midY - 0.5, width: r.width - 20, height: 1))
                }
                continue
            }
            // Actionable when it has an action and is enabled; a status line or greyed item isn't.
            let live = item.isEnabled && (item.action != nil || item.submenu != nil)
            let color = live ? gray(0.1) : gray(0.6)
            let title = item.title, key = shortcut(item), on = item.state == .on, sub = item.submenu != nil
            let ty = r.maxY - pinH / 2
            paints.append { ctx in
                if on { text(ctx, "✓", at: CGPoint(x: r.minX + 7, y: ty), font: menuFont, color: color) }
                text(ctx, title, at: CGPoint(x: r.minX + check, y: ty), font: menuFont, color: color)
                if sub { text(ctx, "›", at: CGPoint(x: r.maxX - inset - 4, y: ty), font: menuFont, color: color) }
                else if !key.isEmpty {
                    text(ctx, key, at: CGPoint(x: r.maxX - inset - textWidth(key, font: menuFont), y: ty), font: menuFont, color: gray(0.55))
                }
            }
            if item.action != nil, item.isEnabled, let id = item.identifier?.rawValue, let ref = ref(id) {
                pins.append(Pin(ref: ref, role: "menuItem",
                                label: title, rect: CGRect(x: r.minX + 4, y: r.maxY - pinH, width: r.width - 8, height: pinH - 1)))
            }
            if let sub = item.submenu {
                let (rr, bb) = layoutMenu(sub, origin: CGPoint(x: r.maxX + 2, y: r.minY - menuInset), paints: &paints, pins: &pins)
                right = max(right, rr)
                bottom = max(bottom, bb)
            }
        }
        return (right, bottom)
    }

    /// A ref from a menu item's identifier (`^N` or `^N#K`).
    static func ref(_ id: String) -> ControlRef? {
        guard id.hasPrefix("^") else { return nil }
        let parts = id.dropFirst().split(separator: "#")
        guard let c = parts.first.flatMap({ UInt32($0) }) else { return nil }
        let k = parts.count > 1 ? UInt32(parts[1]) ?? 0 : 0
        return ControlRef(claim: c, key: k)
    }

    /// An item's shortcut as the menu shows it: ⌘Q.
    @MainActor
    static func shortcut(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        return (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "")
            + (m.contains(.command) ? "⌘" : "") + item.keyEquivalent.uppercased()
    }

    nonisolated(unsafe) static let menuFont = CTFontCreateUIFontForLanguage(.menuItem, 13, nil)!

    static func gray(_ v: CGFloat) -> CGColor { CGColor(red: v, green: v, blue: v, alpha: 1) }

    static func fill(_ ctx: CGContext, _ r: CGRect, _ c: CGColor, radius: CGFloat) {
        ctx.setFillColor(c)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }

    static func line(_ s: String, font: CTFont, color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
            .init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): color]))
    }

    static func textWidth(_ s: String, font: CTFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(s, font: font, color: gray(0)), nil, nil, nil))
    }

    /// Text with its left edge at `p.x`, vertically centred on `p.y`, in a y-down context.
    static func text(_ ctx: CGContext, _ s: String, at p: CGPoint, font: CTFont, color: CGColor) {
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let baseline = p.y + (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
        ctx.textPosition = CGPoint(x: p.x, y: baseline)
        CTLineDraw(line(s, font: font, color: color), ctx)
        ctx.restoreGState()
    }

    /// The status item's SF Symbol, black, flipped for a y-down context.
    @MainActor
    static func symbol(_ name: String, scale: CGFloat) -> CGImage? {
        guard !name.isEmpty, let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) else { return nil }
        let px = Int(16 * scale)
        let ctx = MapCapture.context(px, px)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let s = img.size, k = min(CGFloat(px) / s.width, CGFloat(px) / s.height)
        let r = CGRect(x: (CGFloat(px) - s.width * k) / 2, y: (CGFloat(px) - s.height * k) / 2, width: s.width * k, height: s.height * k)
        img.draw(in: r)
        NSGraphicsContext.restoreGraphicsState()
        // Upside down for the y-down context it is drawn into.
        let flip = MapCapture.context(px, px)
        flip.translateBy(x: 0, y: CGFloat(px))
        flip.scaleBy(x: 1, y: -1)
        flip.draw(ctx.makeImage()!, in: CGRect(x: 0, y: 0, width: px, height: px))
        return flip.makeImage()
    }

    // MARK: Writing

    /// Writes `out/capture.json`, each shot plain and pinned, and each sequence's strip, as
    /// `MapCapture` does. Every image is padded to the largest, so they line up. `places`: per
    /// place claim, how the capture drew it.
    public static func write(_ runs: [(name: String, shots: [Shot], steps: [Outcome])], scale: Float,
                             places: [UInt32: String], out: URL) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let s = CGFloat(scale)
        let w = runs.flatMap(\.shots).map(\.size.width).max() ?? 1
        let h = runs.flatMap(\.shots).map(\.size.height).max() ?? 1
        let pw = Int(w * s), ph = Int(h * s)
        func padded(_ img: CGImage) -> CGImage {
            let ctx = MapCapture.context(pw, ph)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
            ctx.draw(img, in: CGRect(x: 0, y: ph - img.height, width: img.width, height: img.height))
            return ctx.makeImage()!
        }
        var results: [MapCapture.SequenceResult] = []
        for run in runs {
            var shots: [MapCapture.Shot] = []
            var strip: [CGImage] = []
            for (k, shot) in run.shots.enumerated() {
                let base = "\(run.name)-\(k)"
                let next = k < run.steps.count ? run.steps[k].step.ref.label : nil
                let plain = padded(shot.image)
                let pins = MapCapture.pinned(plain, pins: shot.pins.map { ($0.ref.label, $0.rect) }, scale: s, active: next)
                try MapCapture.write(plain, to: out.appendingPathComponent("\(base).png"))
                try MapCapture.write(pins, to: out.appendingPathComponent("\(base).pinned.png"))
                strip.append(pins)
                shots.append(MapCapture.Shot(
                    after: k == 0 ? nil : k - 1, image: "\(base).png", pinned: "\(base).pinned.png", width: pw, height: ph,
                    controls: shot.pins.map {
                        MapCapture.Control(ref: $0.ref.label, claim: $0.ref.claim, key: $0.ref.key, role: $0.role, label: $0.label,
                                           rect: [Int32($0.rect.minX), Int32($0.rect.minY), Int32($0.rect.width), Int32($0.rect.height)])
                    },
                    places: shot.places))
            }
            let steps = run.steps.map {
                MapCapture.StepResult(step: MapCapture.Step(trigger: $0.step.trigger, claim: $0.step.claim, key: $0.step.key),
                                      ref: $0.step.ref.label, outcome: $0.outcome, at: nil)
            }
            let labels = ["Start"] + run.steps.prefix(max(0, strip.count - 1)).enumerated().map {
                "\($0.offset + 1). \($0.element.step.trigger)\($0.element.step.claim == 0 ? "" : " \($0.element.step.ref.label)")"
            }
            try MapCapture.write(MapCapture.strip(strip, labels: labels, scale: s), to: out.appendingPathComponent("\(run.name).strip.png"))
            results.append(MapCapture.SequenceResult(name: run.name, shots: shots, steps: steps, strip: "\(run.name).strip.png"))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(MapCapture.Output(size: [Int32(w), Int32(h)], scale: scale, crop: [0, 0, Int32(w), Int32(h)],
                                         sequences: results,
                                         places: Dictionary(uniqueKeysWithValues: places.map { (String($0.key), $0.value) })))
            .write(to: out.appendingPathComponent("capture.json"))
    }
}
