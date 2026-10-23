# Architecture

Warrant splits a UI into the part we can prove and the part we have to trust, and keeps the
second part small, explicit and checked another way.

```
main thread (Swift, AppKit)   capture events → queue          answer AX and IME queries from the last frame
Lean thread (owns State)      drain queue → update → view → layout → hit map → encode frame
render thread (Swift, Metal)  latest frame → encode draw calls → present on the display link
```

## Lean owns meaning

Everything a person can observe is computed by pure Lean functions, so every property of it is a
statement of the form "for every state s, P (frame s)".

- `State`, `Msg`, `update : State → Msg → State × List Effect`. Effects are data; the host runs them
  and reports results back as messages.
- `view : State → Node`. A tree of boxes, text and controls. A control carries the id of the move
  it performs.
- `layout : Node → Metrics → Laid`. Integer logical pixels. Text sizes come from the host's
  measurements (an assumption, below).
- `hitTest : Laid → Point → Option ClaimId`, plus focus and keyboard routing. Because hit testing
  is in Lean, "a person can press it" is a theorem about the function that actually dispatches the
  click.
- Text editing: buffer, caret, selection, undo, IME composition, all as state and messages.
- `encode : Frame → ByteArray`. The frame carries draw commands, accessibility nodes and
  text-input geometry, so the host never has to call Lean to answer AppKit.

## Claims

A claim is a statement about the product with a durable id. Kinds:

| Kind | What it is |
|---|---|
| `move` | One thing a person can do and what must follow: `enabled`, `apply`, `post`, and a proof that `apply` meets `post` |
| `flow` | A goal reachable through moves, with a checked witness path |
| `invariant` | A property preserved by every move |
| `assume` | Something we take as given about the world, checked at runtime instead of proved |
| `place` | A region of the view where moves appear |

Ids are integers, shown `^N`, never reused or renumbered. `claims.lock` records every id ever
issued, and the build fails when one disappears. Each claim also carries its human description
(`does`, `sees`), which is what a reviewer reads next to the formal statement.

## Swift is a thin host

The host has no application logic. It:

- owns the window and display link, and encodes raw events into bytes for Lean;
- implements `NSTextInputClient`, answering geometry queries from the last frame;
- shapes and measures text with Core Text (and logs every measurement), and rasterizes glyphs into
  an atlas;
- mirrors each frame's accessibility nodes as `NSAccessibilityElement`s, identifier `^N`;
- serves a debug socket for agents and the conformance driver.

## Metal paints

Instanced quads (fill, border, rounded corners by SDF), glyph quads from the atlas, and images.
Checked by pixel probes and goldens, not proved.

## The boundary

Two byte buffers per frame, specified in `docs/frame.md`:

- `events → Lean`: pointer, keys, text input, window size, text metrics.
- `Lean → host`: draw commands, accessibility nodes, text-input geometry.

The encoder and decoder are defined in Lean with a round-trip proof. The Swift decoder is trusted
and checked against a corpus Lean generates.

## What we trust

The full list lives in `docs/trusted.md`: the Lean kernel, compiler and runtime; the Swift
decoder; Core Text's measurements; Metal and the shaders; AppKit's event delivery and IME. Each
entry names how it is checked instead.
