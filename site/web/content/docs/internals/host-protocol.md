---
title: The host protocol
nav: The host protocol
eyebrow: Contributing
lede: Two byte buffers, three functions and three threads: everything that crosses between Lean and the Swift host.
---

A Cairn app is a Lean library with three exported C functions. The host is a Swift program that
calls them. Nothing crosses between the two but **byte buffers**: Lean structures never reach
Swift, because Lean is free to reorder their fields. This page describes the functions, the two
formats and the threads that use them. You need it to write a host, or to understand what the
existing one is trusted with; you don't need it to write an app.

## The three functions

Every app exports the same three functions, from a module of their own. Here are Counter's:

<bongo:include src="lean/Examples/Counter/Abi.lean#counter-abi" />

- `cairn_app_init(w, h, scale)` builds the first runtime state for a window of `w` × `h` logical
  points at a backing scale of `scale` / 100.
- `cairn_app_step(state, events)` runs a batch of encoded events and returns the new state. It
  consumes both arguments: the host drops its reference to the old state.
- `cairn_app_frame(state)` encodes what the window should show now, plus the effects and
  subscription changes of the most recent step. The host asks for one frame after each step and
  runs its effects once.

`cfg` chooses the text metrics: `TextMetrics.host` asks Core Text, through a C function the
Swift host provides. On the Swift side, the host wraps the three functions in a `LeanApp`:

<bongo:include src="host/Sources/CairnCounter/main.swift#counter-leanapp" />

Each app lives in its own Lean library and binary, so there is one `cairn_app_init` per binary.

## Frames: Lean to the host

A frame starts with the magic bytes `CAFR`, a version (currently 4) and reserved flags, then four
parts:

- **Surfaces.** One record per surface: the window, each overlay panel and each menu bar item.
  A window or panel record carries its draws (rects, text, clips, host paints and shapes), its
  accessibility tree, the focused field's text-input state and the cursor. A menu bar item
  carries its button and its menu.
- **Effects.** What to do once: requests, clipboard writes, beeps, quitting.
- **Subscription commands.** Start or stop an ongoing input: a repeating timer, a file watch,
  recording, a global key.
- **Wake.** The earliest timer deadline, in monotonic milliseconds, so the host knows when to
  come back with the clock even if nothing happens.

## Events: the host to Lean

An event batch starts with `CAEV`, its version (currently 2) and flags, then a count and the
records back to back: pointer moves, presses and releases, scrolls, keys, text input, resizes,
window focus, the clock, timer ticks, replies to requests and subscription events. Each record
says which surface it belongs to.

## Conventions

Both formats follow the same rules, so a decoder can be strict:

- Integers are little-endian. Booleans are one byte, `0` or `1`.
- Strings are a 32-bit byte length and UTF-8, with no terminator. Invalid UTF-8 is an error.
- Every record begins with a four-byte head (a tag and up to two small fields) and has a fixed
  part followed by its strings.
- Coordinates are whole logical points, x right and y down from the window's top-left. Colours
  are sRGB, four bytes, not premultiplied. Text ranges count Unicode scalars, not UTF-16 units.
- Unknown codes, trailing bytes, nonzero flags and a section whose body doesn't fill its length
  are errors. A batch that fails to decode is dropped whole.

## What is proved, and what isn't

On the Lean side, decoding an encoded frame gives back the same frame, and the same for events;
the fast encoder is proved equal to its byte-by-byte specification; the accessibility tree
carries exactly the view's controls, in order; clips are balanced. The Swift decoder and encoder
are not proved. They are part of [the trusted base](/docs/internals/trusted-base/), checked by a
shared corpus and by fuzzing.

## Threads

The Swift host runs three threads, and only one of them calls Lean.

| Thread | Does |
|---|---|
| main | turns AppKit events into Cairn events and queues them; applies each new frame: runs its effects, sets the cursor, updates the text-input copy and the accessibility tree. Never calls Lean and never waits for it. |
| Lean | owns the app's state; takes the whole queue as one batch, steps, asks for a frame, decodes it and publishes it |
| render | paints the latest published frame on each display refresh |

Because the Lean thread takes everything queued as one batch, a slow step batches input instead
of falling behind. Each published frame follows exactly one step, so effects run exactly once
however often the window repaints. The Lean thread has a 64 MB stack, because deep structural
recursion overflows the default for secondary threads.

While a window is being resized, the render thread keeps showing the last picture, pinned to the
top-left, for up to 100 ms until a frame for the new size arrives. The main thread never waits, so
a slow frame can't stall AppKit's resize loop.

The input-method protocol is the one place AppKit needs an answer immediately. The host answers
from its own copy of the focused field, predicts the change, and lets Lean's next frame replace
the copy. That prediction is a [trusted assumption](/docs/internals/trusted-base/#the-hosts-input-and-output),
fuzzed against Lean.
