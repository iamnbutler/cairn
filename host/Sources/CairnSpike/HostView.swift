import AppKit
import QuartzCore

/// The window's only view. Turns AppKit events into Lean events, hosts the Metal layer, and
/// mirrors each frame's nodes as accessibility elements answered from the last frame.
final class HostView: NSView, CALayerDelegate {
    let engine: Engine
    private let metalLayer = CAMetalLayer()
    private var axElements: [NSAccessibilityElement] = []
    private var renderThread: RenderThread?

    init(engine: Engine, size: NSSize) {
        self.engine = engine
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func makeBackingLayer() -> CALayer { metalLayer }
    override var acceptsFirstResponder: Bool { true }

    func start(renderer: Renderer) {
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        updateDrawableSize()
        let link = displayLink(target: self, selector: #selector(tick))
        renderThread = RenderThread(link: link, renderer: renderer, layer: metalLayer, view: self)
        updateDrawableSize()  // again, now that the render thread can take the viewport
        renderThread?.start()
    }

    // Called on the render thread's run loop.
    @objc func tick(_ link: CADisplayLink) { renderThread?.drawIfNeeded() }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        renderThread?.setViewport(SIMD2(Float(bounds.width), Float(bounds.height)))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        engine.send([.resize(Int32(newSize.width), Int32(newSize.height))])
    }

    override func viewDidChangeBackingProperties() { updateDrawableSize() }

    private func point(_ e: NSEvent) -> (Int32, Int32) {
        let p = convert(e.locationInWindow, from: nil)
        return (Int32(p.x.rounded(.down)), Int32(p.y.rounded(.down)))
    }

    override func mouseDown(with e: NSEvent) {
        let (x, y) = point(e)
        engine.send([.down(x, y)])
    }

    override func mouseUp(with e: NSEvent) {
        let (x, y) = point(e)
        engine.send([.up(x, y)])
    }

    /// An accessibility press is a real click at the node's centre, so it goes through Lean's
    /// hit testing like any other click.
    func press(_ node: Frame.Node) {
        let (x, y) = node.center
        engine.send([.down(x, y), .up(x, y)])
    }

    // MARK: Accessibility mirror

    func mirror(_ frame: Frame) {
        axElements = frame.nodes.map { node in
            let el = NodeElement(node: node, host: self)
            el.setAccessibilityParent(self)
            el.setAccessibilityRole(node.role == 1 ? .button : .staticText)
            el.setAccessibilityLabel(node.label)
            el.setAccessibilityEnabled(true)
            if node.claim != 0 { el.setAccessibilityIdentifier("^\(node.claim)") }
            // Parent space is y-up even though this view is flipped.
            el.setAccessibilityFrameInParentSpace(
                NSRect(x: CGFloat(node.x), y: bounds.height - CGFloat(node.y) - CGFloat(node.h), width: CGFloat(node.w), height: CGFloat(node.h)))
            return el
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { axElements }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
}

final class NodeElement: NSAccessibilityElement {
    let node: Frame.Node
    weak var host: HostView?

    init(node: Frame.Node, host: HostView) {
        self.node = node
        self.host = host
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        guard node.role == 1 else { return false }
        DispatchQueue.main.async { [host, node] in host?.press(node) }
        return true
    }
}

/// Draws the latest frame on its own thread, driven by the view's display link.
final class RenderThread: @unchecked Sendable {
    private let link: CADisplayLink
    private let renderer: Renderer
    private let layer: CAMetalLayer
    private weak var view: HostView?
    private let lock = NSLock()
    private var viewport = SIMD2<Float>(1, 1)
    private var drawn = -1
    private var viewportChanged = true

    init(link: CADisplayLink, renderer: Renderer, layer: CAMetalLayer, view: HostView) {
        self.link = link
        self.renderer = renderer
        self.layer = layer
        self.view = view
    }

    func start() {
        let t = Thread { [self] in
            link.add(to: .current, forMode: .common)
            RunLoop.current.run()
        }
        t.name = "cairn.render"
        t.qualityOfService = .userInteractive
        t.start()
    }

    func setViewport(_ v: SIMD2<Float>) {
        lock.lock()
        viewport = v
        viewportChanged = true
        lock.unlock()
    }

    func drawIfNeeded() {
        guard let engine = view?.engine else { return }
        let (frame, version) = engine.snapshot()
        lock.lock()
        let vp = viewport
        let changed = viewportChanged
        viewportChanged = false
        lock.unlock()
        guard let frame, version != drawn || changed else { return }
        drawn = version
        renderer.draw(frame, in: layer, viewport: vp)
    }
}
