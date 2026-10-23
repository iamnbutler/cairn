# Goal: M1, a proved TodoMVC on the Mac

Cairn is research into building user interfaces where every thing a person can do is a
**claim** with a durable id, and every claim carries machine-checked evidence. M1 is the first
demo that shows the whole loop end to end on a small, well-known app.

TodoMVC is the subject because it is small, completely specified, has text input, and is the
benchmark formal UI testing already uses: Quickstrom's temporal-logic spec found bugs in about
half of its implementations. It is big enough to need every layer of the stack and small enough
to finish.

## The demo

`make demo` opens a native macOS window running TodoMVC. Its state, update, view, layout, hit
testing, focus and text editing are written in Lean. A thin Swift host turns events into bytes and
paints Lean's frames with Metal.

## Done means

1. **The app.** Every behaviour in the TodoMVC spec works: add with Enter (trimmed, empty ignored),
   toggle, toggle all, edit on double-click (Enter or blur saves, Escape cancels, empty deletes),
   delete (shown on hover), filters All, Active and Completed, clear completed, and the item
   counter with its plural. Text fields support typing, caret movement, selection, deletion,
   copy and paste, and IME composition.
2. **Claims.** Every action a person can take is a `move` with a durable id. Flows, invariants and
   assumptions are claims too. `claims.lock` records every id ever issued; the build fails when
   one disappears, is reused, or has no description.
3. **Proofs.** Checked by Lean, with no `sorry` and no axioms beyond Lean's standard three
   (`propext`, `Classical.choice`, `Quot.sound`), enforced by an audit in `make check`:
   - each move does what its claim says (`post`);
   - the invariants hold in every reachable state: the counter equals the active items, the
     visible list is the filter applied to the items, item ids are unique;
   - **presence:** a control tagged with a move's id is in the frame if and only if the move is
     enabled;
   - **pressable:** for every enabled pointer move, at window sizes at or above the minimum, hit
     testing at its control's centre returns that move, so it is visible, unclipped and on top;
   - the frame and event encodings round-trip (`decode (encode x) = x`);
   - every flow has a checked witness path from the initial state.
4. **The host.** Swift and Metal on three threads (AppKit main, a Lean thread that owns the state,
   a render thread). The main thread never waits on Lean. Text is shaped by Core Text and drawn
   from a glyph atlas. Every node is mirrored as an accessibility element whose identifier is its
   claim id (`^12`).
5. **Conformance.** A driver generates move sequences from the Lean model, performs them on the
   running app through its debug socket as real pointer and key events, and compares the
   accessibility tree and the frame with the model after every step. Pixel probes check that each
   control's box is painted. 1,000 generated sequences pass.
6. **Measured.** Lean's update + view + layout + encode time at 100, 1,000 and 10,000 nodes, and
   frame times in the running app, recorded in `bench/`.
7. **The map is a build output.** The claims compile to a map (the map skill's format) with an
   evidence column computed from the build: proved, model-checked, conformance-tested, seen.
   Screenshots come with pins placed from the layout, not by hand.
8. **Written down.** `docs/trusted.md` lists everything the proofs trust, and why each item is
   checked another way. `docs/frame.md` specifies the boundary byte format.

## Not in M1

More than one user, network effects, an LLM, persistence beyond a file, iOS or other platforms,
animation, rich text, accessibility beyond the mirror (VoiceOver actions are a stretch), scrolling
(a stretch), and Ace.

## Order of work

1. **Boundary spike.** Lean static library linked into a Swift and Metal app; two buttons with
   claims; clicks round-trip; one presence proof; timing at 100/1k/10k nodes. This de-risks
   everything else.
2. **Foundations in parallel.** Claim language and ledger; the UI core (tree, style, layout, hit
   testing, focus); text editing; frame and event encoding with proofs; the Metal renderer and
   glyph atlas; the AppKit host with IME and the accessibility mirror; the debug socket; research
   notes on prior art.
3. **TodoMVC** on the foundations, then the proofs over it.
4. **Conformance, benchmarks and the generated map.**
