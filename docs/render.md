# Renderer and text

Workstream F: `host/Sources/CairnRender` paints a frame's `[Draw]` with Metal, and gives Lean the
text metrics it lays out with. Both halves shape text through one object, `TextSystem.shared`,
so what Lean measures is what gets drawn. This code is trusted (docs/trusted.md); it is kept
small and checked by goldens, pixel probes and an end-to-end metrics test.

## API

```swift
let r = try Renderer()                                 // one per render thread
r.draw(frame: f, into: drawable, scale: 2)            // encode, present, commit
r.draw(frame: f, into: texture, scale: 2)             // returns the committed MTLCommandBuffer
try r.image(f, scale: 2)                               // offscreen render + readback (Image)
try r.probe(f, at: Point(x: 40, y: 13), scale: 2)      // the colour painted at a logical point
```

`Renderer` is single-threaded. `TextSystem` is thread-safe and shared with the metrics export.
The target can be any size; `scale` maps logical points to its device pixels (`frame.size` is
not used for painting). Before drawing, the target is cleared to `clearColor` (white).

`probe` renders offscreen and returns the un-premultiplied colour of the device pixel that
contains the point's centre `(x + ½, y + ½)`. Conformance checks use it for "this control's box
is painted": probe the control's centre (or any point clear of its label and corners) and
compare with its fill.

## Painting

Draws are painted strictly in list order; a later draw is on top. Consecutive draws of one kind
(rects, or glyphs) under the same clip form one batch, drawn with one instanced call. A change of
kind or clip, or a glyph needing a different atlas page, starts a new batch. Nothing is
reordered across kinds.

**Rects** are instanced quads shaded by a signed distance field in **device pixels**: the
fragment's distance `d` to the rounded box edge gives coverage `saturate(½ − d)`, an exact box
filter on straight edges and a one-device-pixel ramp on curves at every scale. Every rect is
converted to device pixels by snapping each edge, `⌈v·s − ½⌉` (round half down), never origin
and size separately, so boxes that share an edge in logical points share it in device pixels at
any scale: no seams at 1.5x (`tiles@1.5x` golden, `noSeamsAtFractionalScale`). Since snapped
edges sit on pixel boundaries, straight edges have no blended fringe at all.

- Radius is scaled, not snapped, and clamped to half the shorter side (pills, circles).
- Border is **inside** the rect: an inner rounded box inset by the border width with radius
  `max(r − w, 0)`; the ring between the two is painted in the border colour over the fill
  (the fill extends under the border, as CSS `background-clip: border-box`). Border widths round
  half down but a nonzero width is at least one device pixel.
- Colours are sRGB bytes, premultiplied, blended in gamma space into `bgra8Unorm` (AppKit's
  look). The host should set its `CAMetalLayer.colorspace` to sRGB so those bytes mean sRGB on
  P3 panels (workstream G).

**Clips** are a stack of scissor rects. `pushClip r` intersects `r` (snapped with the same edge
rule as fills) with the current clip; `popClip` restores the previous one. A clip equal to a
rect admits exactly that rect's pixels (`clipMatchesFill`). Draws under an empty clip are
dropped on the CPU. A `popClip` with nothing to pop is ignored and counted in `lastStats`.
Scissor state splits batches; Zed's per-instance clip distances would not, but frames in M1 have
few clips, and the scissor stack is simpler to check. Rounded clips are not supported.

**Text.** `Draw.text(origin, font, color, string)`: `origin` is the left end of the baseline.
The string is shaped as one `CTLine`, and each `CTRun` is drawn with its own font, which may be
a fallback (emoji, CJK, symbols). Glyphs come from an atlas:

- Rasterised by Core Text (`CTFontDrawGlyphs`) at the backing scale, using a copy of the run's
  font at `size × scale`.
- **Grayscale** antialiasing into one-channel (`r8Unorm`) pages, tinted by the text colour in the
  shader. Font smoothing (Core Graphics' colour-dependent stroke dilation) is **off**: macOS has no
  LCD antialiasing since 10.14, smoothing would need the dilation level in the cache key, and
  Zed and Ghostty both default to this. Text is a little lighter than AppKit's, most visibly
  light-on-dark.
- Colour glyphs (fonts with `traitColorGlyphs`, i.e. emoji) go to premultiplied `bgra8Unorm`
  pages and ignore the text colour (its alpha still applies).
- **Subpixel positioning**: each glyph's device-pixel x is split into a whole pixel (the quad
  origin) and a fraction quantised to 4 bins, baked into the bitmap. The baseline y is rounded to
  a whole device pixel. Quads therefore sit on whole pixels and sample the atlas 1:1 with nearest
  filtering, so text never blurs. Core Graphics' own subpixel quantisation is off. Colour glyphs
  snap to whole pixels.
- Cache key: (run font, glyph id, subpixel bin, scale). Pages are 2048² and append-only (shelf
  packing), so frames in flight never see texels change. When more than 8 pages exist at the
  start of a frame, the renderer waits for the GPU and drops the whole atlas.

Instance buffers are three pooled slots recycled in the command buffer's completion handler
(at most three frames in flight). Shaders compile from source at `Renderer.init`, so the package
needs no Metal build step. `RectInstance` and `GlyphInstance` strides are checked against the
shader's at init.

## Fonts

`Font` maps to Core Text in one place (`Fonts.make`), used by both drawing and metrics:

| Field | Mapping |
|---|---|
| `family` | 1 → `NSFont.monospacedSystemFont`; anything else → `NSFont.systemFont` |
| `size` | points, clamped to 1…1024 (0 would make Core Text pick 12) |
| `weight` | CSS 100–900, rounded to the nearest hundred and clamped: 100 ultraLight, 200 thin, 300 light, 400 regular, 500 medium, 600 semibold, 700 bold, 800 heavy, 900 black |
| `italic` | the italic symbolic trait; the upright face if the font has none |

## Metrics for Lean

### The consistency guarantee

`TextSystem.shape(font, string)` builds the `CTLine` once per (font, string) and caches it. The
renderer draws that line's glyph runs; the metrics export reads that line's caret offsets. Lean's
`TextMetrics.host` is a thin decoder over the export. So for any text draw Lean emits, the glyphs
painted and the offsets Lean laid out with come from the same Core Text object (checked end to
end by `LeanMetricsTests`, which calls Lean's `TextMetrics.host` through the real extern and
compares it with the renderer's line).

### ABI

```c
// Exported by Swift (@_cdecl), CairnRender/Metrics.swift.
int32_t cairn_text_metrics(uint32_t family, uint32_t size, uint32_t weight, uint8_t italic,
                           const uint8_t *utf8, size_t len, int32_t *out, size_t cap);
```

Writes `[ascent, descent, offset_0, …, offset_n]` to `out` (at most `cap` values) and returns the
full count, `n + 3`, where `n` is the number of Unicode scalars. Values are whole logical points.
Invalid UTF-8 is repaired with U+FFFD (Lean strings are always valid). Thread-safe.

On the Lean side (`lean/Cairn/Text/Host.lean`, glue in `lean/c/text_host.c`):

```lean
@[extern "cairn_lean_text_metrics"]
opaque raw (family size weight : UInt32) (italic : UInt8) (s : @& String) : ByteArray
def TextMetrics.host : TextMetrics
theorem TextMetrics.host_valid : TextMetrics.host.Valid
```

The C glue allocates a `ByteArray` of `4·(n + 3)` bytes (`n` from the Lean string's scalar
count), calls `cairn_text_metrics` into it, and returns it empty if the count disagrees. Lean
decodes little-endian int32s. Font fields cross as `UInt32`, saturating (the frame encoder must
do the same so a huge `Nat` means the same font in both places).

`TextMetrics.host` then **normalises**: offset 0 is forced to 0, the rest pass through a running
maximum from 0, and ascent and descent through `max 0`. For a well-behaved host this is the
identity (the Swift tests check the host's output is already valid), and it makes `host_valid`
a theorem rather than an assumption.

### Offsets and rounding

For a string with scalars `c₀ … cₙ₋₁`:

1. Shape the whole string as one `CTLine`. Never measure prefixes: kerning makes them disagree
   (at 40 pt the caret after "A" in "AV" is left of "A"'s own width; `offsetsComeFromOneLine`).
2. Boundary `i` is UTF-16 index `uᵢ = Σ_{k<i} utf16Count(cₖ)`, so no query lands inside a
   surrogate pair (Core Text answers 0 there).
3. `xᵢ = CTLineGetOffsetForStringIndex(line, uᵢ)`, the primary caret offset. Boundaries inside a
   grapheme cluster report the cluster's end; we keep that.
4. `round(x) = max(0, ⌈x − 1/256⌉)`: up to a whole point, with values within 1/256 pt above a
   whole point snapping down to it (so float noise like 20.000001 is 20). Monotone and
   `round(0) = 0`.
5. `offsetᵢ = max(offsetᵢ₋₁, round(xᵢ))`, `offset₀ = 0`. For left-to-right text Core Text's
   offsets already increase, so the running max changes nothing; for RTL or bidi text (out of
   scope in M1) it keeps the array nondecreasing, and the carets are wrong.
6. The last offset is also raised to `round(typographic width)`, so the box covers the whole
   advance.
7. `ascent = round(CTFontGetAscent(font))`, `descent = round(CTFontGetDescent(font))` for the
   requested (not fallback) font.

Why this gives `TextMetrics.Valid`: the array has one entry per boundary, `n + 1`, plus nothing
else (`size`); entry 0 is 0 (`zero`); each entry is the max of the previous and something, so
the array is nondecreasing (`mono`); `round` never returns a negative (`ascent`, `descent`).
Lean re-establishes all five by `normalise` anyway.

What the rounding guarantees about painting: every glyph's advance box lies within
`[0, width]` up to 1/256 pt (`advancesInsideBox`). On the painted pixels
(`InkTests`, 8 fonts × 24 strings at 1x and 2x): for upright left-to-right text (Latin,
accents, CJK, Hangul, emoji) all ink lies inside Lean's box, `origin.x … origin.x + width` by
`baseline − ascent … baseline + descent`. Italic glyphs overhang their advance and Arabic sits
lower than the requested font's descent; the measured overhang is at most 1 pt on any side, so
anything that must contain such text pads by 1 pt.

### Caching

Lines are cached by (font, string) in one dictionary behind a lock, cleared wholesale at 8,192
entries. Layout on the Lean thread measures a string before the render thread draws it, so the
render thread normally hits the cache (see bench/render.md for the miss cost).

### Linking without the host

`text_host.o` is a `moreLinkObjs` of the `Cairn` library: Lake puts it in `libcairn_Cairn.a` and
links it into every Lean executable. It defines `cairn_text_metrics` **weakly**, returning −1
("no host"); then `raw` is empty and `TextMetrics.host` returns the `mono` stand-in's numbers.
So `bench`, `audit` and Lean tests link and run without Swift. In the app, the Swift host's
strong `cairn_text_metrics` replaces the weak one at link time; `Cairn.Text.Host.hostLinked ()`
reports which is in use, and `LeanMetricsTests` fails if the stand-in is linked. Never evaluate
`TextMetrics.host` at elaboration time (`#eval`, `#guard`): the interpreter has no native code to
call.

The host must initialise the `Cairn` Lean module (directly or through an app module that imports
`Cairn.Text.Host`) before Lean calls `TextMetrics.host`.

## Tests

`make test` (part of `make check`) runs `swift test`, headless and offscreen:

- **Goldens** (`host/Tests/CairnRenderTests/Goldens/*.png`): rects, borders, clips (nested,
  disjoint, empty, popped), fonts (weights, italic, mono, sizes, light on dark), scripts (emoji,
  CJK, Hangul, combining accents), paint order, and tiled boxes, at 2x and some at 1x and 1.5x.
  Tolerance: geometry-only scenes allow 0.2% of pixels to differ by more than 8/255; text scenes
  0.5–1% by more than 24/255 (glyph rasterisation may shift between OS releases). Each run
  writes renders to `$CAIRN_RENDER_OUT` or `$TMPDIR/cairn-render/` (plus `*.golden.png` on a
  mismatch); `CAIRN_UPDATE_GOLDENS=1 swift test` rewrites the goldens.
- **Probes**: exact fills with no fringe at 1x/1.5x/2x/3x, borders inside, thin borders never
  vanish, one-device-pixel antialiasing, no seams at 1.5x, nested clips, empty clips, clip equals
  fill, paint order and batching across kinds, colour emoji, atlas reset.
- **Metrics**: `Valid` for 8 fonts × 24 strings through the C ABI, short buffers, invalid UTF-8,
  kerning from one line, clusters and surrogates, rounding, font mapping, cache.
- **Ink**: the painted pixels of every text draw against Lean's box (above).
- **End to end** (`CairnRenderLeanTests`): Lean's `TextMetrics.host`, through `@[extern]`, the
  C glue and the Swift export, equals the renderer's `ShapedLine` for 5 fonts × 11 strings.

`make bench` also runs `RenderBench` (bench/render.md).
