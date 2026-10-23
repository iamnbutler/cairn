---
title: Text rendering in GPU UI frameworks on macOS (Core Text, glyph atlases, AA, gamma)
urls:
  - https://github.com/zed-industries/zed/tree/604a0ff023ec/crates/gpui_apple/src
  - https://github.com/alacritty/crossfont/tree/0c34d199b151/src/darwin
  - https://github.com/ghostty-org/ghostty/tree/08a9518340e1/src/font/face
  - https://www.warp.dev/blog/adventures-text-rendering-kerning-glyph-atlases
  - https://wezterm.org/config/lua/config/font_rasterizer.html
  - MacOSX.sdk CoreText.framework/Headers/CTLine.h, CTFont.h (Xcode SDK on this machine)
date: 2026-10-23
relevance: 5
---

# Text rendering in GPU UI frameworks on macOS

How Zed (GPUI), Alacritty (crossfont), Ghostty, Warp and WezTerm get from a string to glyph
quads, plus an empirical probe of Core Text caret offsets (`raw/ctprobe.swift`, output in
`raw/ctprobe-output.txt`). Commits: zed `604a0ff023ec`, crossfont `0c34d199b151`, ghostty
`08a9518340e1`.

## Findings

### 1. Everyone rasterises grayscale (alpha-only) glyphs on macOS

- GPUI hard-codes grayscale on macOS:
  `crates/gpui_apple/src/text_system.rs:221` `TextRenderingMode::Grayscale`
  (from `recommended_rendering_mode`). Its subpixel (LCD) path and gamma table exist for
  other platforms; the table is `#[allow(dead_code)]` and credited "Adapted from
  https://github.com/microsoft/terminal/…/dwrite.cpp" (`crates/gpui/src/platform.rs:1676-1681`).
- GPUI's atlas for monochrome glyphs is one channel:
  `crates/gpui_apple/src/metal_atlas.rs:146` `pixel_format = metal::MTLPixelFormat::A8Unorm;`
  (polychrome/emoji goes to `BGRA8Unorm`, :150). Atlas textures start at 1024×1024
  (`metal_atlas.rs:129-138`).
- Ghostty renders non-colour glyphs into an alpha-only bitmap in a **linear gray** colour space:
  `src/font/face/coretext.zig:424` `.space = try macos.graphics.ColorSpace.createNamed(.linearGray),`
  and colour (emoji/sbix) glyphs into Display P3 (:428).
- Since Mojave (10.14), macOS does not do LCD subpixel AA by default. Community reports only,
  Apple never documented it; the `CGFontRenderingFontSmoothingDisabled` default is reported to
  work by some and not by others (stanislas.blog 2018, HN item 17476873). Treat LCD AA as dead
  on macOS. On Retina at 2x grayscale is what system apps show.

### 2. "Font smoothing" on modern macOS means stroke thickening, and it depends on text colour

- crossfont, `src/darwin/mod.rs:265-271`:
  > "The AppleFontSmoothing user default controls font smoothing on macOS, which increases the
  > stroke width. By default it is unset, and the system behaves as though it is set to 2 … The
  > valid values are integers from 0 to 3. Any other type, including a boolean, does not change
  > the behavior."
  It rejects booleans by checking `objCType` (`mod.rs:296-301`).
- GPUI replicates CoreGraphics' colour-dependent dilation, `text_system.rs:225-237`:
  > "When font smoothing is enabled, CoreGraphics thickens glyph strokes by an amount that
  > depends on the foreground color's luminance. We replicate the logic used by CoreGraphics to
  > select between the different levels of dilation."
  `let level = ((4.0 * luminance) + 0.5).floor() as i32;` (:234), clamped 0–4. The level is
  part of the glyph cache key (`crates/gpui/src/text_system.rs:1305`), and at raster time it
  draws with gray fill = `dilation * 0.25` and `set_should_smooth_fonts(true)` (:510-513).
  So one glyph may need up to five atlas entries per colour luminance bucket.
- Ghostty makes it opt-in and off by default (`src/config/Config.zig:345`
  `@"font-thicken": bool = false`), drawing with gray fill = `thicken_strength/255`
  (`coretext.zig:503-507`), and pads the canvas 1px for it (:392-396):
  > "We make an assumption that font smoothing ("thicken") adds no more than 1 extra pixel to
  > any edge."
- crossfont rasterises white-on-**opaque**-black RGB (`mod.rs:416` `let bg_a = if is_colored { 0.0 } else { 1.0 };`)
  and smooths iff the user default allows (:427). Smoothing needs something to draw against;
  GPUI and Ghostty instead get the thickening through the gray fill level on an alpha-only context.

### 3. Subpixel positioning is horizontal only, quantised to 3 or 4 variants, and the atlas key includes it

- GPUI: `SUBPIXEL_VARIANTS_X: u8 = 4`, `SUBPIXEL_VARIANTS_Y: u8 = 1`
  (`crates/gpui/src/text_system.rs:49-52`). In `paint_glyph`
  (`crates/gpui/src/window.rs:4851-4863`) the origin is scaled to device pixels, quantised to
  quarter pixels, the integer part becomes the quad origin and the fraction becomes the variant:
  `round_half_toward_zero(glyph_origin.x.0 * SUBPIXEL_VARIANTS_X as f32) / SUBPIXEL_VARIANTS_X as f32`.
  Emoji are snapped to whole pixels instead (:4955).
- GPUI draws the shift inside the bitmap and widens it by a pixel
  (`text_system.rs:452-458` "Add an extra pixel when the subpixel variant isn't zero to make
  room for anti-aliasing") and pads raster bounds by 1px each side (:440-441). It turns Core
  Graphics' own quantisation off (`:507` `set_allows_font_subpixel_quantization(false)`), as
  Ghostty does (`coretext.zig:490-494` "We don't want subpixel quantization, since we very
  carefully manage the position of our glyphs ourselves"). crossfont leaves it on (`mod.rs:428-429`)
  because its terminal cells are pixel-aligned anyway.
- Warp (blog, 2022-07-27): first snapped glyphs to whole pixels "to avoid GPU blending", which
  meant "we're not respecting the precise positioning information provided by our shaping
  engine" (bad kerning, "V A"). Fix: "we split each pixel into 3 equally-sized subpixels" and
  round each glyph to the nearest. Rejected interpolating between variants and 3x supersampling
  as not worth it.
- GPUI samples the atlas with `mag_filter::linear` (`shaders.metal:666`) but places quads on
  integer device pixels, so the linear filter never actually blends texels. If a quad ever
  lands on a fractional device pixel, the glyph blurs.

### 4. Shaping: one CTLine per run of text, UTF-16 indices throughout

- GPUI builds a `CFMutableAttributedString`, converting UTF-8 → UTF-16 ranges, and reads back
  `run.string_indices()` (UTF-16) and converts to UTF-8 with a forward-only converter
  (`text_system.rs:540-640`, converter :643-668).
- GPUI's trick to stop Core Text merging adjacent runs (and forming ligatures across a style
  boundary): alternate the font size by one ULP, `text_system.rs:566-579`
  `px(f32::from(font_size).next_up())` … `break_ligature = !break_ligature;`.
- `text_system.rs:554`: "note: replace_str may silently ignore codepoints it dislikes (e.g., BOM
  at start of string)". Index maps break if the CFString isn't the string you think it is;
  they have tests for BOM and ZWNJ (`:805-930`).
- Fallback: crossfont asks for `CTFontCopyDefaultCascadeListForLanguages` with a hard-coded
  `["en"]` (`mod.rs:70` "TODO fixme, hardcoded en for english."), drops descriptors with no
  path (which removes `.`-prefixed system fallbacks like ".Apple Symbol Fallback") and adds
  "Apple Symbols" back by hand (:76-85). GPUI relies on CTLine's built-in fallback and maps the
  run's actual `kCTFontAttributeName` back to a font id (`id_for_native_font`, :403). The CTFont
  header: `CTFontCreateForString` "is to be used when the current font does not cover the given
  range of the string. The current font itself will not be returned, but preference is given to
  fonts in its cascade list."
- `CTFontDrawGlyphs` header (CTFont.h): "This function will modify the CGContext's font, text
  size, and text matrix … These attributes will not be restored. The given glyphs should be the
  result of proper Unicode text layout operations (such as CTLine). Results from
  CTFontGetGlyphsForCharacters (or similar APIs) do not perform any Unicode text layout."

### 5. Core Text caret offsets, measured (macOS 27 SDK, system UI font 13pt; `raw/ctprobe-output.txt`)

CTLine.h: `CTLineGetOffsetForStringIndex` "returns the graphical offset(s) corresponding to a
string index, suitable for … drawing a custom caret", "The primary offset along the baseline for
charIndex, or 0.0 in the event of failure." `CTLineGetStringIndexForPosition` "corresponds to the
character before which the next character should be inserted". `CTLineEnumerateCaretOffsets`
(10.11+) "is invoked once for each logical caret edge in the line, in left-to-right visual order."
Indices are UTF-16 into the line's string.

| String | What came back |
|---|---|
| `"AV"` | caret at 1 = 8.27, but `"A"` laid out alone = 8.68. Kerning: prefix widths ≠ caret offsets. |
| `"e\u{301}x"` | index 1 (the combining acute, inside the cluster) = 7.35, same as index 2. Scalar boundaries inside a cluster collapse to the cluster's end. |
| `"a👨‍👩‍👧b"` | index 1 = 7.10, indices 3,4,6,7,9 all = 26.10. Every boundary inside the ZWJ sequence reports the cluster's trailing edge. |
| `"…🙂"` mid-surrogate (u16 index 5) | **0.00**, i.e. the failure value, not an error. Inside the ZWJ family the mid-surrogate index happened to return 26.10. |
| `"abאבc"` | index 2: primary 15.01, secondary 31.08; index 3: 22.74; index 4: 15.01 / 31.08. **Not monotonic in logical order**, with two carets at the direction boundary. |
| `"Hello"` 13.5pt | fractional offsets throughout (9.91, 17.51, 20.81, …). |

### 6. Not everyone uses Core Text to rasterise

- WezTerm: "The only available implementation is `FreeType`" (font_rasterizer docs), even on
  macOS; Core Text is used only to locate fonts. Its text consistently looks different from
  native apps, which is the trade it makes for cross-platform consistency.

## Pitfalls

1. **Prefix measuring is wrong.** Measuring `s.prefix(i)` as its own line gives a different
   answer from the caret offset at `i` (kerning, contextual shaping): 8.68 vs 8.27 for "AV".
   Shape the whole string once and read every caret from that one CTLine.
2. **Scalar indices ≠ UTF-16 indices.** Converting a scalar index to UTF-16 must count surrogate
   pairs. A wrong conversion lands mid-surrogate, and Core Text quietly returns 0.0 (caret jumps to
   the line start) instead of failing.
3. **Scalar boundaries inside grapheme clusters are not caret positions.** Core Text reports
   the cluster's trailing edge for every inner boundary, so arrow keys over "é" (decomposed) or a
   ZWJ emoji will "stick" for several presses with the caret not moving, and backspace will delete
   half a cluster.
4. **Bidi breaks monotonic offsets** and gives two carets at direction runs (secondary offset).
5. **Font smoothing ≠ subpixel AA.** On modern macOS it is colour-dependent stroke dilation.
   If you turn it on, the glyph cache key needs the dilation level (GPUI) and the canvas needs
   1px padding (Ghostty). If you leave it off, text looks thinner than AppKit's, most visibly
   light text on dark backgrounds.
6. **`AppleFontSmoothing` parsing**: an unset key means "on (level 2)"; a boolean is ignored by
   macOS; only integer 0 means off (crossfont).
7. **Glyph quads must start on integer device pixels**, with the fractional part baked into the
   bitmap as a subpixel variant. Fractional quad origins plus linear sampling blur text. At a
   fractional backing scale (e.g. 1.5 on some external setups, or zoom), an integer *logical*
   origin is not an integer *device* origin.
8. **Core Graphics' own subpixel quantisation fights yours**: turn it off when you quantise
   positions yourself (GPUI, Ghostty).
9. **Blend space**: blending glyph alpha in a gamma-encoded `bgra8Unorm` target is what macOS
   text has always looked like. Switching to linear blending (an `_sRGB` target) makes dark text
   thinner and light text bolder (Ghostty's `alpha-blending` docs). Ghostty's
   "linear-corrected" fix needs the **background colour per glyph**, which a terminal has and a
   general UI does not.
10. **Fallback fonts must be discovered from the shaped runs**, not assumed: read
    `kCTFontAttributeName` from each CTRun and key the atlas by the actual font. Hard-coded
    cascade lists (crossfont's `"en"`) miss CJK and symbol fonts.
11. **CFString edits can drop codepoints** (BOM at start), which silently shifts every later
    index (GPUI comment, :554).
12. Emoji (sbix/COLR) glyphs need an RGBA atlas, premultiplied-alpha handling (GPUI swaps
    RGBA-premultiplied → BGRA-straight, :530-534) and whole-pixel placement.

## Counter-evidence

- WezTerm skips Core Text rasterisation entirely and is usable. Matching AppKit's look exactly
  is a goal, not a requirement.
- Alacritty quantises with Core Graphics (subpixel quantisation on) and keeps an opaque RGB
  canvas, and its output looks fine because terminal cells are pixel-aligned. Cairn's
  proportional UI text is not.
- Warp found 3 variants enough; GPUI uses 4. Neither published a measurement of the visible
  difference, and Warp calls more precision "perceptually largely indistinguishable".

## For Cairn

- **F (renderer/text) — `cairn_text_offsets`**: build one CTLine per (font, string), walk the
  string's unicode scalars, convert to UTF-16 indices by summing `utf16.count`, and call
  `CTLineGetOffsetForStringIndex` at each scalar boundary. Never measure prefixes. Round each
  offset the same way (e.g. `floor(x + 0.5)`). Rounding is monotone, so it preserves `mono`, but
  only if the float input is monotone (next point).
- **F**: `TextMetrics.Valid.mono` (`lean/Cairn/Text/Metrics.lean`) is false for real RTL text
  (measured: 15.01, 22.74, 15.01). For M1, either declare text LTR-only in `docs/trusted.md` and
  have the host **check** monotonicity on every measurement (log and clamp with a running max if
  it fails, so Lean's assumption holds), or carry both offsets. The runtime check is the
  `assume` claim's evidence.
- **D/F**: since M1 doesn't model grapheme clusters, caret motion over a cluster will appear to
  stall. Either add grapheme boundaries to `TextMetrics` (the host can report which scalar
  boundaries are cluster boundaries, e.g. from Swift `Character` indices), or add the TodoMVC
  test strings to a known-limitations list. Record repeated offsets as a symptom in the
  measurement log.
- **F — atlas**: A8 atlas for text, BGRA for emoji. Key = (CTFont identity incl. fallback font,
  size, glyph id, subpixel x variant (3–4), scale factor, dilation level if smoothing). Place quads
  at `floor(device_x)`. Draw a run with `CTFontDrawGlyphs` using the CTRun's own font and positions,
  never `CTFontGetGlyphsForCharacters`.
- **F — look**: start with grayscale, smoothing off, gamma-space blending into `bgra8Unorm`
  (what Zed does). Add GPUI-style dilation only if text looks thin next to AppKit in pixel
  goldens. Don't adopt linear-corrected blending: Cairn doesn't know the background under each glyph.
- **F/B — baseline**: `Draw.text` origin is an integer logical baseline. At 2x that's an integer
  device row, which is good. Snap the baseline to a device pixel (`round(y*scale)/scale`) before
  rasterising so vertical position never needs a y variant (GPUI uses `SUBPIXEL_VARIANTS_Y = 1`).
- **G**: read `AppleFontSmoothing` the way crossfont does if smoothing is ever enabled, and
  list it in `docs/trusted.md` as an input to rendering that Lean never sees.
