import AppKit
import CairnFrame
import Metal
import QuartzCore

/// The window's logical size and backing scale, as the render thread sees them.
public struct Viewport: Equatable, Sendable {
    public var size: CGSize
    public var scale: CGFloat
    public init(size: CGSize, scale: CGFloat) { self.size = size; self.scale = scale }
    public var pixelSize: CGSize { CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded()) }
}

/// Paints frames. The seam between the host (G) and the renderer (F): the host owns the layer,
/// the thread and the drawable; the renderer encodes one frame into it.
public protocol FrameRenderer: AnyObject {
    var device: MTLDevice { get }
    /// Set the layer's pixel format and anything else the renderer needs. Called once on the
    /// main thread before the first frame.
    func configure(_ layer: CAMetalLayer)
    /// Encode `frame` into `drawable`, present it and commit. Called on the render thread only.
    /// `frame` is in logical points, y down; `viewport` maps them to the drawable's pixels.
    func draw(_ frame: Frame, to drawable: CAMetalDrawable, viewport: Viewport)
}

/// The render thread: a run loop driven by the view's display link. Each tick it paints the
/// newest frame if it is new or the viewport changed, and never touches Lean or AppKit state.
final class RenderLoop: NSObject, @unchecked Sendable {
    private let engine: Engine
    private let renderer: FrameRenderer
    private let layer: CAMetalLayer
    private let lock = NSLock()
    private var viewport: Viewport
    private var viewportChanged = true
    /// The event that told Lean about the current viewport, and when it was sent.
    private var viewportSeq: UInt64 = 0
    private var viewportTime = 0.0
    /// How long to hold the old picture for a frame at the new size before drawing a stale one.
    static let resizeWait = 0.1
    private var drawn = -1
    private var link: CADisplayLink?
    private var thread: Thread?

    init(engine: Engine, renderer: FrameRenderer, layer: CAMetalLayer, viewport: Viewport) {
        self.engine = engine
        self.renderer = renderer
        self.layer = layer
        self.viewport = viewport
    }

    /// The viewport can be set before the thread starts; the first tick uses the latest value.
    /// `seq` is the resize or scale event that tells Lean about it.
    func setViewport(_ v: Viewport, seq: UInt64?) {
        lock.lock()
        if v != viewport { viewport = v; viewportChanged = true }
        if let seq { viewportSeq = seq; viewportTime = hostNow() }
        lock.unlock()
    }

    /// Starts the thread with a display link made by the view (main thread).
    func start(link: CADisplayLink) {
        self.link = link
        nonisolated(unsafe) let link = link  // handed to the render thread, used only there
        let t = Thread {
            link.add(to: .current, forMode: .common)
            RunLoop.current.run()
        }
        t.name = "cairn.render"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() { link?.invalidate() }

    /// Display link callback, on the render thread.
    @objc func tick(_ link: CADisplayLink) {
        guard let p = engine.latest else { return }
        lock.lock()
        let vp = viewport
        let changed = viewportChanged
        // Live resize: hold the old picture (pinned top-left) until Lean has a frame at the new
        // size, rather than drawing a frame laid out for the old one. Give up after resizeWait.
        let stale = p.throughSeq < viewportSeq && hostNow() - viewportTime < Self.resizeWait && drawn >= 0
        if !stale { viewportChanged = false }
        lock.unlock()
        guard !stale, p.version != drawn || changed else { return }
        let pixels = vp.pixelSize
        guard pixels.width >= 1, pixels.height >= 1 else { return }
        if changed || layer.drawableSize != pixels { layer.drawableSize = pixels }
        guard let drawable = layer.nextDrawable() else {
            lock.lock(); viewportChanged = viewportChanged || changed; lock.unlock()
            return
        }
        // A size change between our drawableSize and nextDrawable: drop it, draw next tick.
        guard drawable.texture.width == Int(pixels.width), drawable.texture.height == Int(pixels.height) else {
            lock.lock(); viewportChanged = true; lock.unlock()
            return
        }
        let version = p.version
        let engine = self.engine
        drawable.addPresentedHandler { d in
            // presentedTime is 0 when Core Animation doesn't report it (seen on macOS 27 with a
            // windowed, composited layer); the handler itself runs just after the present, so
            // its time is the fallback.
            engine.presented(version: version, at: d.presentedTime > 0 ? d.presentedTime : hostNow())
        }
        drawn = version
        renderer.draw(p.frame, to: drawable, viewport: vp)
    }
}
