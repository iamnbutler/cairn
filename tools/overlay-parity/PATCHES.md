# Patches to the copied Overlay.swift

`Overlay.swift` here is `~/code/yap/App/Overlay.swift` with the patches below; pristine copies of both
sources are in `orig/`. `Overlay.metal` is unchanged (`diff orig/Overlay.metal Overlay.metal` is empty);
it is compiled to `default.metallib` next to the `yapref` binary, which `device.makeDefaultLibrary()`
finds unpatched (a bare executable's main bundle is its directory).

What each patch is for:

- `Overlay.renderer`, `Overlay.panel`: access only (`private` -> internal / `private(set)`), so the
  harness can inject values into the real renderer and capture the real panel. The harness otherwise
  drives the real `Overlay`: `begin(1)` (makePanel + show + place), `update(1, phase:, text:)` (which
  derives `active` and `tint` exactly as the original) and `hide(1)` (the 0.18 s alpha fade).
- `WaveRenderer.paused` / `makeView()`: the MTKView is always paused with `enableSetNeedsDisplay = true`;
  the harness calls `view.draw()` once the values are set.
- `WaveRenderer.levels`, `cuts`, `elapsed`: `private` -> internal, injected. New `time`, injected.
- `render(in:)`: no clock, no `level()`, no history shift; `time` uniform comes from `self.time`.
  Everything else (uniforms, buffers 0/1/2, tint resolution, scale) is unchanged.
- `presented` callback via `drawable.addPresentedHandler`, plus a `frames` counter, so the harness
  waits until the frame it drew has been presented before capturing.
- Not patched: the clock. The harness sets `model.started = Date(timeIntervalSinceReferenceDate: 0)` and
  `model.stopped = Date(timeIntervalSinceReferenceDate: clockSeconds)`, so the original `clock(at:)`
  shows `Int(clockSeconds)` whatever the phase.

```diff
--- orig/Overlay.swift	2026-10-23 22:10:02
+++ Overlay.swift	2026-10-23 22:10:04
@@ -14,8 +14,8 @@
 @MainActor
 final class Overlay {
     let model = OverlayModel()
-    private let renderer: WaveRenderer
-    private var panel: NSPanel?
+    let renderer: WaveRenderer  // yapref: was private (harness injects values)
+    private(set) var panel: NSPanel?  // yapref: was private (harness captures it)
     /// The recording the panel is showing. A transcript can land after the
     /// next recording has begun, and must not overwrite it or hide it.
     private var owner = 0
@@ -311,20 +311,26 @@
     var active = true
     var tint = Palette.red
     var paused = true {
-        didSet { view?.isPaused = paused }
+        // yapref: the view stays paused and draws only when asked (draw()).
+        didSet { view?.isPaused = true }
     }
+    /// yapref: injected instead of the clock: the shader's `time` uniform.
+    var time: Float = 0
+    /// yapref: called once the frame drawn by the last draw has been presented.
+    var presented: (@MainActor @Sendable (_ frame: Int) -> Void)?
+    private(set) var frames = 0  // yapref: frames drawn
 
     private let level: @MainActor () -> Float
     private let device = MTLCreateSystemDefaultDevice()
     private var queue: MTLCommandQueue?
     private var pipeline: MTLRenderPipelineState?
-    private weak var view: MTKView?
-    private var levels = [Float](repeating: 0, count: WaveRenderer.history)
+    private(set) weak var view: MTKView?  // yapref: was private
+    var levels = [Float](repeating: 0, count: WaveRenderer.history)  // yapref: injected, was private
     private var shown: Float = 0
-    private var cuts: [Float] = []
+    var cuts: [Float] = []  // yapref: injected, was private
     /// Seconds of tape: advances only while recording, so the ruler and the
     /// reel stop when you do.
-    private var elapsed: Float = 0
+    var elapsed: Float = 0  // yapref: injected, was private
     private var lastFrame = ContinuousClock.now
     private let started = ContinuousClock.now
 
@@ -350,7 +356,8 @@
         view.colorPixelFormat = .bgra8Unorm
         view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
         view.preferredFramesPerSecond = 60
-        view.isPaused = paused
+        view.isPaused = true  // yapref: was `paused`
+        view.enableSetNeedsDisplay = true  // yapref: draw on demand
         view.delegate = self
         self.view = view
 
@@ -372,16 +379,9 @@
     }
 
     private func render(in view: MTKView) {
-        let now = ContinuousClock.now
-        if active { elapsed += Self.seconds(lastFrame.duration(to: now)) }
-        lastFrame = now
+        // yapref: no clock and no level(): `elapsed`, `time` and `levels` are
+        // injected, and drawing does not shift the history.
 
-        // Rises at once and falls slowly, so speech reads as a shape rather
-        // than flicker.
-        shown = max(active ? level() : 0, shown * 0.9)
-        levels.removeFirst()
-        levels.append(shown)
-
         guard let pipeline, let queue,
             let pass = view.currentRenderPassDescriptor,
             let drawable = view.currentDrawable,
@@ -395,7 +395,7 @@
                 Float(resolved.redComponent), Float(resolved.greenComponent),
                 Float(resolved.blueComponent), 1),
             size: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
-            time: Self.seconds(started.duration(to: now)),
+            time: time,  // yapref: was Self.seconds(started.duration(to: now))
             count: Float(levels.count),
             active: active ? 1 : 0,
             elapsed: elapsed,
@@ -413,6 +413,12 @@
         }
         encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
         encoder.endEncoding()
+        frames += 1
+        let frame = frames
+        let presented = self.presented
+        drawable.addPresentedHandler { _ in  // yapref: lets the harness wait for it
+            Task { @MainActor in presented?(frame) }
+        }
         buffer.present(drawable)
         buffer.commit()
     }
```
