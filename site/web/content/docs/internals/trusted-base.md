---
title: The trusted base
nav: The trusted base
eyebrow: Reference
lede: Everything the proofs rely on but don't prove, and how each piece is checked instead.
---

A Cairn proof is about the Lean model: the app's state, its view, its layout, hit testing and the
bytes it sends. Between those bytes and the pixels a person sees sits code nobody proves: the
Swift host, AppKit, Core Text, Metal and the GPU. That code is the **trusted base**.

Cairn's rule is to keep it small and to write it down. Each piece of it is an **assumption**: a
statement about the world that is taken as given, stated as an `assume` claim with an id, and
checked another way, most often by a fuzzer that runs the real host code against Lean's proved
side or an independent oracle. Cairn's [claim pages](/packages/cairn/claims/#assumptions) list every
assumption with its evidence.

## How an assumption is checked

There are three kinds of check, and an assumption usually has more than one.

- **Fuzzed.** The trusted-base fuzzer (`make fuzz-trusted`, and a short run in `make check`) runs
  random cases through the real host code and compares the result with Lean's proved code or
  another oracle. Each fuzz check names the assumption it is evidence for, so its result shows
  as **fuzzed** in `cairn doc`. A failure prints the command that replays it.
- **Tested.** Swift unit tests, golden images, the frame corpus and each app's self test
  (`make selftest`), which drives the host headlessly through its real threads.
- **Reviewed.** Some things, like the table that maps AppKit key bindings to Lean events, are
  written and checked by hand. They are listed as such, so a reader knows.

Fuzzing has found real bugs this way: the Swift frame decoder ignoring a reserved field, a NUL in
a file path silently cutting the path, and wrong caret positions on letter-spaced text. Each was
fixed in the host, not papered over in Lean.

## What is assumed

### Text and the renderer

- **Text metrics match what is painted.** Lean lays text out using caret offsets, ascent and
  descent that Core Text reports. It is assumed that the glyphs Metal paints sit inside the box
  those numbers describe. Lean normalises whatever bytes come back, so the layout theorems hold
  for any metrics; what is assumed is that the metrics are true. Fuzzed across fonts, sizes,
  weights, tracking and edge-case text (^906, ^907).
- **Wrapped lines are what Core Text paints.** Lean breaks a paragraph using one shaping of the
  whole string, then the renderer shapes each line on its own. It is assumed the two agree to
  within a point or so on left-to-right text (^990), and that Lean's breaks are the ones Core
  Text's own typesetter would choose (^991). That every line fits, and that the lines tile the
  text, is proved.
- **The renderer paints the frame.** Draws are painted in order, rects cover exactly their
  pixels, nothing paints outside its clip. Checked by golden images at 1x, 1.5x and 2x and
  pixel probes.
- **Host-drawn content stays in its box.** An app can register a Metal shader to draw inside a
  box (Yap's level display does). It is assumed that it changes no pixel outside that box
  (^1004). Fuzzed by rendering random frames with and without the paint and comparing every
  pixel outside.

### The frame encoding

Lean's encoder and decoder are proved to round-trip. The Swift decoder and encoder are not. It is
assumed they agree with Lean byte for byte: checked by a corpus of 300 frames and 300 event
batches compared in both languages, and fuzzed with mutated frames that both sides must accept
or reject alike (^901, ^902). The format is on [the host protocol](/docs/internals/host-protocol/)
page.

### The host's input and output

- **Input.** AppKit delivers events in order; pointer positions are rounded down to whole
  points; consecutive pointer moves and scrolls are coalesced. Key mapping uses AppKit's own key
  bindings inside a text field and a reviewed table outside one.
- **Text input.** UTF-16 offsets are converted to Unicode scalar indices (fuzzed, ^903). Between
  an input-method call and the next frame, the host answers from its own copy of the field and
  predicts the change; any disagreement with Lean's next frame is recorded (fuzzed, ^904). The
  geometry it gives the input method comes from the renderer's shaping (fuzzed, ^905).
- **Accessibility.** The accessibility tree is a translation of the frame's accessibility nodes.
  The role mapping is reviewed by hand.
- **The Lean runtime.** It is initialised once, on one thread with a 64 MB stack; the main and
  render threads never call Lean.

### Effects

Lean decides every effect: which timers are set and when they fire, which replies are delivered,
which subscriptions run. The runtime's handling is proved whatever the host sends. What the host
is trusted with is that what it sends is **true**: the time, the deadline, and the outcome of each
request.

| Assumption | Id | What is checked |
|---|---|---|
| The clock | ^908 | one clock per batch; monotonic time never goes backwards and is never ahead of the batch |
| Wake-ups | ^909 | a wake comes at or after its deadline, within 40 ms under load, and never after it was cleared |
| Reading and writing files | ^910, ^911 | files round-trip under random Unicode names; writes are atomic; failures map to the documented faults |
| Sounds | ^912 | every system sound name resolves; any other name is `notFound` |
| HTTP | ^913 | method, URL, headers and body arrive as given; replies come back exactly; header injection is refused |
| One reply per request | ^914 | each request is answered at most once, under its own id |
| Timers that repeat | ^915 | ticks only while started, about once per period |

Yap needed more: appending to and listing files, deleting, permissions, the app in front, the
microphone, a global hot key, typing into another app, uploads and secrets. Each of those is an
assumption with its own fuzz check too (^960–^971, ^1000–^1003 and ^1005). Every device is replaced by a
fake in the fuzz suites, so `make check` never records audio, watches the keyboard or types into
another app.

### Menus and panels

A menu bar app's menu and its overlay panels are real AppKit objects. It is assumed that the
native menu shows the frame's records (^940), that choosing an item reports its reference
(^941), that opening and closing are reported once each (^942), that a panel never takes focus
or clicks (^943), and that a panel sits where its anchor says (^944). All five are fuzzed against
detached menus and panels, never shown on screen.

### Conformance

Conformance runs drive the real app and compare every frame with the Lean model. They are
trusted too, in specific ways: events are injected at the view, not through the window server;
key events are built as a US keyboard would produce them; no real input method runs; and frames
are compared through two JSON printers, one per language. A passing run says the app matched the
model for the sequences it ran, judged through those pieces.

## What isn't assumed

The list above is what you have to trust. Everything else, the app's logic, its view, layout, hit
testing, focus, the runtime's handling of every effect and the encoding on Lean's side, is proved
in Lean, and `make check` audits every theorem's axioms. See
[proving a claim](/docs/guide/proving/).
