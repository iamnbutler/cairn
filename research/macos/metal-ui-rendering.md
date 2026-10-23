---
title: Metal UI rendering on macOS (SDF quads, clipping, batching, pacing, resize, colour, latency)
urls:
  - https://github.com/zed-industries/zed (crates/gpui_apple, crates/gpui_macos, crates/gpui @ 604a0ff023ec)
  - https://github.com/ghostty-org/ghostty (src/renderer @ 08a9518340e1)
  - https://github.com/kovidgoyal/kitty (glfw/cocoa_displaylink.m @ 3867ffa92bef)
  - https://zed.dev/blog/videogame
  - https://iquilezles.org/articles/distfunctions2d/
  - https://raphlinus.github.io/ui/graphics/gpu/2021/10/22/swapchain-frame-pacing.html
  - https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction
  - https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable()
  - https://developer.apple.com/documentation/quartzcore/cametallayer/colorspace
  - https://developer.apple.com/documentation/quartzcore/cametallayer/maximumdrawablecount
  - https://developer.apple.com/documentation/quartzcore/cametallayer/displaysyncenabled
  - https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)
  - https://developer.apple.com/documentation/quartzcore/cadisplaylink
  - https://developer.apple.com/documentation/quartzcore/cametaldisplaylink
  - https://developer.apple.com/documentation/metal/mtldrawable/presentedtime
date: 2026-10-23
relevance: 5
---

# Metal UI rendering on macOS

What GPU-drawn UIs on the Mac actually do for rounded rects, clipping, draw order, buffering,
frame pacing, live resize, colour and latency, and where each goes wrong. Code quoted at the
commits in the frontmatter. Apple doc text was taken from the developer.apple.com JSON
(`/tutorials/data/documentation/<path>.json`) on 2026-10-23.

## 1. Rounded rects with borders by SDF

**Inigo Quilez, `sdRoundedBox` (exact, per-corner radii).** Note that it is written y-up:

```glsl
float sdRoundedBox( in vec2 p, in vec2 b, in vec4 r )
{
    r.xy = (p.x>0.0)?r.xy : r.zw;
    r.x  = (p.y>0.0)?r.x  : r.y;
    vec2 q = abs(p)-b+r.x;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r.x;
}
```

With y down (Metal framebuffer coordinates, Cairn's geometry) `p.y>0` is the *bottom* half, so
copying IQ's corner packing swaps top and bottom radii.

**Zed picks the corner by quadrant explicitly in y-down space**
(`crates/gpui_apple/src/shaders.metal:1045-1058`):

```metal
float pick_corner_radius(float2 center_to_point, Corners_ScaledPixels corner_radii) {
  if (center_to_point.x < 0.) {
    if (center_to_point.y < 0.) {
      return corner_radii.top_left;
```

**Zed's SDF and AA threshold work in device pixels** (`shaders.metal:126-128`, `:1075-1089`):

> "Signed distance field threshold for inclusion of pixels. 0.5 is the minimum distance between
> the center of the pixel and the edge. `const float antialias_threshold = 0.5;`"

```metal
float signed_distance_to_inset_quad =
    // 0 inside the inset quad, and positive outside
    length(max(float2(0.0), corner_center_to_point)) +
    // 0 outside the inset quad, and negative inside
    min(0.0, max(corner_center_to_point.x, corner_center_to_point.y));
return signed_distance_to_inset_quad - corner_radius;
```

All of Zed's quad inputs are `Bounds_ScaledPixels` (device pixels). The 0.5 threshold is only
"half a pixel" because the distance is in device pixels.

**Borders: inner edge as a second SDF, zero-width borders made AA-free**
(`shaders.metal:133-209`):

> "0-width borders are reduced so that `inner_sdf >= antialias_threshold`. The purpose of this is
> to not draw antialiasing pixels in this case."

> "Negative when inside the border `float border_sdf = max(inner_sdf, outer_sdf);`"

For unequal border widths at a rounded corner Zed uses a quarter-ellipse inner edge
(`shaders.metal:204-205`, `ellipse_radii = max(0, corner_radius - reduced_border)`), with a
comment that it is an approximation. It also has a fast path that returns the fill when there is
no radius and no border (`shaders.metal:112-119`).

**Zed splits border-only quads into four strips** so the GPU doesn't shade the transparent
interior (`crates/gpui/src/window.rs:4723-4760`): "Splitting a border-only quad around its empty
interior avoids shading every transparent pixel inside large outlines."

**Pixel snapping: snap edges, not origin + size** (`crates/gpui/src/window.rs:3306-3341`):

```rust
fn snap_bounds(&self, bounds: Bounds<Pixels>) -> Bounds<ScaledPixels> {
    let left = round_to_device_pixel(bounds.left().0, scale_factor);
    let top = round_to_device_pixel(bounds.top().0, scale_factor);
    let right = round_to_device_pixel(bounds.right().0, scale_factor).max(left);
```

> "Rounds half-to-zero but clamps any non-zero input up to 1 dp so thin strokes do not disappear."
> (border widths, `:3318`)

> "Floors the near edge and ceils the far edge, producing a strict superset of the raw region."
> (clip/content masks, `:3329`)

Rounding each edge independently keeps two boxes that share an edge in logical space sharing it
in device space too. Rounding origin and size separately can open or overlap a one-pixel seam
at fractional scales.

## 2. Clipping

**Zed clips rectangles with hardware clip distances in the vertex shader, not scissor or
stencil** (`shaders.metal:54`, `:78-97`, `:1127-1141`):

```metal
float clip_distance [[clip_distance]][4];
...
float4 clip_distance = distance_from_clip_rect(unit_vertex, quad.bounds, quad.content_mask.bounds);
```

Each instance carries its own `content_mask`, so clips don't break a batch the way
`setScissorRect` (encoder state) would. Zed's content masks are axis-aligned rectangles only:
there is **no rounded clipping** in GPUI. Primitives entirely outside their mask are dropped on
the CPU (`crates/gpui/src/scene.rs:87-95`, `if clipped_bounds.is_empty() { return; }`).

Options for a rounded clip, none of which Zed uses: a stencil pass per clip (breaks batches and
costs a pass), or passing the clip's rounded-rect parameters per instance and multiplying
coverage by the clip's SDF in the fragment shader (no extra passes, more instance data).

## 3. Batching and painter's order across primitive kinds

The blog post (zed.dev/blog/videogame) described a fixed order: "It starts by drawing all
shadows, followed by all rectangles, then all glyphs, and so on." **The current code no longer
does that.** It gives every primitive an `order` (from a bounds tree / layer stack), sorts each
kind by it, and merges the per-kind streams so that a batch of one kind ends as soon as another
kind has a lower order (`crates/gpui/src/scene.rs:152-162`, `:288-345`):

```rust
orders_and_kinds.sort_by_key(|(order, kind)| (order.unwrap_or(u32::MAX), *kind));
...
.next_if(|shadow| (shadow.order, batch_kind) < max_order_and_kind)
```

Sprites also sort by atlas texture (`(sprite.order, sprite.tile.texture_id.index)`, `:157`)
so a batch never needs two textures. Each batch is one `draw_primitives_instanced_base_instance`
(`crates/gpui_apple/src/metal_renderer.rs:977`).

## 4. Buffers in flight

- Zed uses a **pool of instance buffers returned in the command buffer's completion handler**
  (`metal_renderer.rs:57-107`, `:594-603`). Shared + write-combined storage on unified memory,
  `Managed` otherwise: "Buffers are write only which can benefit from the combined cache".
  Default buffer 2 MiB, growing up to `MAX_INSTANCE_BUFFER_SIZE = 256 * 1024 * 1024` (`:41`).
- Ghostty keeps a fixed triple-buffered set: "Triple buffering. `pub const swap_chain_count = 3;`"
  (`src/renderer/Metal.zig:37-38`), with write-combined buffers (`Metal.zig:245-258`).
- Apple: "If all drawables are in use, the layer waits up to one second for one to become
  available, after which it returns nil" (`nextDrawable()` docs). `maximumDrawableCount` "You
  can set this value to 2 or 3 only … The default value is 3."
- Zed turns the timeout off: `objc2_layer.setAllowsNextDrawableTimeout(false);`
  (`metal_renderer.rs:220`), so its `nextDrawable` can block indefinitely instead of returning
  nil after 1 s.

## 5. Frame pacing and which thread draws

- **Zed renders on the main thread.** `CVDisplayLink` ticks from its own io thread are merged
  into a GCD `data_add` dispatch source whose target queue is `DispatchQueue::main()`
  (`crates/gpui_macos/src/display_link.rs:303-307`); a burst of ticks coalesces into one
  callback. The file's header records two crash classes from `CVDisplayLink` teardown
  (`display_link.rs:1-51`): "CVDisplayLink has no safe teardown: `CVDisplayLinkStop` merely flags
  the link's io thread to exit 'soon' and returns immediately". Zed's fix is one immortal link per
  display. It also deliberately uses a lock with priority donation for the high-priority io thread.
- kitty also uses `CVDisplayLink` and notes: "CVDisplayLink is deprecated replace with
  CADisplayLink via [NSScreen displayLink] once base macOS version is 14"
  (`glfw/cocoa_displaylink.m:8`).
- **Ghostty renders on its own renderer thread, but into an IOSurface**, then sets
  `layer.contents` on the main thread (`src/renderer/metal/IOSurfaceLayer.zig:50-90`, `setSurface` at :53):
  "Sets the layer's `contents` to the provided IOSurface. Makes sure to do so on the main thread
  to avoid visual artifacts." It does not use `CAMetalLayer` at all.
- `NSView.displayLink(target:selector:)` (macOS 14+): "Returns a new display link whose
  callback will be invoked in-sync with the display the view is on. If the view is hidden, or not
  on any display, the callback will not be invoked." `CADisplayLink`: callbacks run on the run
  loop you `add(to:forMode:)`, which is how Cairn's spike gets them on its render thread. "Actual
  frame rates are always a factor of the maximum refresh rate".
- `CAMetalDisplayLink` (macOS 14) adds `preferredFrameLatency`: "The only acceptable values are
  1.0 and 2.0", and "The final latency may be bigger if the system needs more time, such as for
  windowed modes on macOS."
- `displaySyncEnabled` defaults to true; false trades tearing for latency.
- Raph Levien on pacing: "Doing things the simplest way will generally optimize for throughput at
  the expense of latency", and "The optimum time for starting the work is the deadline minus the
  (say) 99.99 percentile of that distribution".

## 6. Live resize: the hard one

Apple, `presentsWithTransaction`: "By default … CAMetalLayer displays the output of a rendering
pass to the display as quickly as possible and asynchronously to any Core Animation
transactions. Core Animation doesn't guarantee that the Metal content arrives in the same frame
as other Core Animation content." With it on: "first commit the command buffer … Then, call its
waitUntilScheduled() … Finally, call the drawable's present() method", and "don't use the
present(_:) method on the command buffer".

**Zed draws synchronously on the main thread during resize.** Its `displayLayer:` (called because
of `setNeedsDisplayOnBoundsChange(true)`, `metal_renderer.rs:221`) stops the display link,
switches to transactional present, renders, then switches back
(`crates/gpui_macos/src/window.rs:3324-3343`):

```rust
lock.renderer.set_presents_with_transaction(true);
lock.stop_display_link();
drop(lock);
callback(RequestFrameOptions { ... });
...
lock.renderer.set_presents_with_transaction(false);
lock.start_display_link();
```

and presents exactly as Apple says (`metal_renderer.rs:553-560`):
`command_buffer.commit(); command_buffer.wait_until_scheduled(); drawable.present();`.
It does the same on `windowDidBecomeKey:` to avoid "tab flicker" (`window.rs:3190-3216`).

**Ghostty also draws synchronously on resize** (`displayCallback` calls `drawFrame(true)`,
`Metal.zig:156-160`; `present(sync)` sets contents directly, `:237-243`), and **throws away
async frames of the wrong size** (`IOSurfaceLayer.zig:100-125`):

> "asynchronously drawn frames can sometimes finish just after a synchronously drawn frame during
> a resize, and if we don't discard the improperly sized surface it creates jank."

It also pins old content to the top-left instead of stretching it (`IOSurfaceLayer.zig:31-34`):
"The layer gravity is set to top-left so that the contents aren't stretched during resize
operations before a new frame has been drawn." (Apple: the default `contentsGravity` is `resize`.)

winit asks AppKit to keep redrawing a layer-backed view during resize:
`setLayerContentsRedrawPolicy(NSViewLayerContentsRedrawPolicy::DuringViewResize)`
(`winit-appkit/src/view.rs:887`).

## 7. Colour space and blending

- Apple, `CAMetalLayer.colorspace`: "The default value is nil, indicating that the rendered
  content isn't color-matched."
- Zed sets Display P3 on the layer when asked (`metal_renderer.rs:194-209`); pixel format stays
  `BGRA8Unorm` (`:190`), so blending happens on gamma-encoded values.
- Ghostty makes the blend space a setting (`src/config/Config.zig:384-412`):
  > "`native` - Perform alpha blending in the native color space for the OS. On macOS this
  > corresponds to Display P3 … `linear` - … will eliminate the darkening artifacts around the
  > edges of text … but makes dark text look much thinner than normal and light text much
  > thicker."

  The default on macOS is `native`. Linear blending is done by rendering to `bgra8unorm_srgb`
  (`Metal.zig:188-193`): "Using an `*_srgb` pixel format makes Metal gamma encode the pixels
  written to it *after* blending, which means we get linear alpha blending".
- Ghostty also makes the layer opaque and sets `contentsScale` from the window to avoid "blurry
  rendering" (`Metal.zig:123-126`). Zed: `layer.set_opaque(!transparent)` "Support direct-to-display
  rendering if the window is not transparent" (`metal_renderer.rs:211-213`).

## 8. Measuring input-to-photon latency

- `MTLDrawable.addPresentedHandler` plus `presentedTime`: "The host time, in seconds, when the
  drawable was displayed onscreen … The property value is 0.0 if the drawable hasn't been
  presented or if its associated frame was dropped."
- `NSEvent.timestamp` is seconds since boot. `presentedTime` is host time (the
  `CACurrentMediaTime` / mach clock). Zed samples both clock domains for its frame signals:
  "Instant cannot be constructed from Mach ticks, so sample both clock domains."
  (`display_link.rs:132`). Its `RequestFrameOptions { signal_at, signal_source }` carries the
  vsync timestamp into the frame for this kind of accounting (`window.rs:3350-3364`).
- Software timestamps miss compositor and panel latency. Calibrate end-to-end with an external
  method (a high-speed camera, or a Typometer-style screen-reading tool) at least once.
- Raph Levien: "the only way to really get to the source of truth is measurement on a real,
  physical system"; "On mac, the Instruments application gives nice timing data."

## Pitfalls

1. **AA ramp in the wrong units.** `saturate(0.5 - dist)` only gives a one-device-pixel ramp if
   `dist` is in device pixels. In points at 2x it smears every edge over two pixels (Zed works in
   `ScaledPixels`).
2. **Corner order flips with y.** IQ's `sdRoundedBox` packs radii for y-up. In Metal's y-down
   space, pick by quadrant as Zed does (`shaders.metal:1045`).
3. **Zero-width borders still draw an AA fringe** unless the inner SDF is pushed past the
   threshold (`shaders.metal:139-143`).
4. **Snapping origin and size separately leaves seams** at 1.5x and other fractional scales. Snap
   edges (`window.rs:3306`), clamp thin strokes up to 1 dp, and grow clips outward (floor near
   edge, ceil far edge).
5. **Scissor rects break batches**, since each clip change is a new encoder state. Per-instance
   clip distances (`[[clip_distance]]`) keep one draw per kind. Rounded clips need a stencil or a
   shader SDF; Zed has neither.
6. **A fixed kind order ("all quads, then all glyphs") is wrong for overlap.** A popover quad must
   cover earlier text. Zed moved to per-primitive order with kind-interleaved batches
   (`scene.rs:288-345`).
7. **Reusing or freshly allocating one buffer per frame.** Writing a buffer the GPU is still
   reading corrupts frames; `makeBuffer` every frame costs allocations. Pool buffers and release
   them in `addCompletedHandler` (Zed), or use a fixed triple set (Ghostty).
8. **`nextDrawable` blocks.** By default it waits up to 1 s and then returns nil. With timeouts
   off (Zed) it waits forever. On a thread that also services the display link, a blocked
   `nextDrawable` stalls pacing. Hidden or occluded windows stop getting callbacks.
9. **Off-main presentation and live resize don't mix.** Asynchronous presents land out of step
   with the window frame, so content wobbles or stretches. Both Zed and Ghostty fall back to a
   synchronous main-thread draw during resize (Zed with `presentsWithTransaction` +
   `waitUntilScheduled` + `drawable.present()`), and Ghostty drops late frames whose size doesn't
   match.
10. **Default `contentsGravity` is `resize`**, so the old frame is stretched until a new one
    arrives. Use top-left.
11. **`colorspace == nil` means no colour matching.** sRGB byte values show up as native-gamut
    (P3) on modern Macs, more saturated than the same colour drawn by AppKit. Pixel probes on the
    drawable still pass, so this hides from tests.
12. **Gamma-space vs linear blending is a look, not a bug fix.** Linear blending thins dark text
    (Ghostty). Matching the OS (native, gamma-space) is the default for good reason.
13. **`CVDisplayLink` teardown races** crashed Zed twice. Prefer `NSView.displayLink` /
    `CADisplayLink` (macOS 14+), which also follow the view across screens.
14. **Autorelease pools on a custom render thread.** Drawables and command buffers are
    autoreleased. Ghostty wraps every frame in an explicit pool (`Metal.zig:162-175`). Without
    one on a long-lived thread, drawables can stay retained and `nextDrawable` starves.

## Counter-evidence

- The Zed blog's "shadows, then rectangles, then glyphs" order is what many write-ups repeat, but
  current GPUI code shows it was replaced (§3). Don't copy the blog.
- Zed draws on the main thread and is still fast enough at 120 Hz. A render thread is not
  required for smoothness; Cairn chose one so the main thread never waits on Lean, not for GPU
  reasons.
- Ghostty avoids `CAMetalLayer` entirely (IOSurface + `layer.contents`), which sidesteps drawable
  pool blocking and lets it check sizes on the main thread. `CAMetalLayer` is not the only
  workable route.
- Zed's `setAllowsNextDrawableTimeout(false)` goes against Apple's default. Neither choice is
  clearly right: a timeout gives you nil and a dropped frame, while no timeout can hang the
  drawing thread.

## For Cairn

**Workstream F (renderer):**

- The spike's `quad_fragment` computes `dist` from `in.local`, which is in **logical points**
  (`viewport` is `bounds` in points). At 2x the AA ramp is two device pixels wide. Multiply
  geometry by the backing scale in the vertex shader and do the SDF in device pixels, or divide
  by `fwidth(dist)`.
- Adopt Zed's quad model: per-corner radii picked by y-down quadrant, outer and inner SDFs for
  borders, zero-width AA suppression, the fill-only fast path, and border-only strip splitting if
  fill rate matters. Snap edges (not origin and size) to device pixels at draw time. Lean's
  integer logical points times a fractional scale is exactly the 1.5x seam case.
- `pushClip`/`popClip` in `Draw`: implement as per-instance clip rects with `[[clip_distance]]`
  so clips don't split batches. Decide now whether rounded clips are in M1; if so, use a
  per-instance clip SDF rather than a stencil.
- Batch by the order of `frame.draws` (already painter's order). Break a batch only when the kind
  or atlas texture changes. Never reorder kinds globally.
- Replace the per-frame `makeBuffer` with three pooled buffers recycled in
  `addCompletedHandler`.
- Set `layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)` so Lean's sRGB bytes mean sRGB
  on P3 panels, keep `bgra8Unorm` (gamma-space blending, matching AppKit and Ghostty's `native`),
  and record the choice in `docs/trusted.md`. Pixel probes read the drawable and can't see colour
  matching.
- Wrap each `draw` in `autoreleasepool {}`.
- Latency: register `drawable.addPresentedHandler` and log `presentedTime` minus the timestamp of
  the newest event folded into the frame. Both sit on the mach host clock; verify that once
  against a camera. Write results to `bench/`.

**Workstream G (host):**

- Live resize is the one place "the main thread never waits on Lean" will hurt. Choose, and
  write down, one of: (a) during `inLiveResize`, the main thread waits for one Lean frame at the
  new size and presents with `presentsWithTransaction` (Zed's approach, which bends the rule only
  during resize); (b) keep async but set `contentsGravity = .topLeft` and drop frames whose size
  doesn't match the current `drawableSize` (Ghostty's approach), accepting a sliver of stale
  content at the edges. Either way, `drawableSize` is set on main while the render thread calls
  `nextDrawable`; hand the size to the render thread and have it set `drawableSize` itself
  before acquiring.
- `NSView.displayLink` is the right primitive (no `CVDisplayLink` teardown races, follows
  screens). Expect no callbacks while hidden or occluded, and resume cleanly.
- `layer.isOpaque = true` for the main window. Keep `framebufferOnly = true` except in a debug
  build that needs to read pixels back for probes (Zed does exactly this split,
  `metal_renderer.rs:215-219`, debug + test-support only). The pixel-probe tool in workstream J will need a readback path.
