# Boundary spike (2026-10-23)

Question: can a Lean static library own an app's state, view, layout and hit testing inside a
Swift and Metal app, with the main thread never waiting on Lean, and is it fast enough?

Answer: yes. A two-button counter (`lean/Examples/Counter.lean`, `host/Sources/CairnSpike`)
runs with real clicks, accessibility presses and a proved presence theorem.

## What was checked

- **Clicks round-trip.** A real mouse click (and an accessibility press, which the host turns
  into a click at the node's centre) goes Swift → event bytes → Lean `step` → hit test →
  `apply` → frame bytes → Metal and the accessibility mirror. `make selftest` drives the same
  path headlessly: three clicks on ^1, one on ^2, and a press released off the control.
- **Presence is proved.** `Examples.Counter.reset_present_iff`: ^2 is in the frame exactly when
  reset is enabled. It goes through the layout function (`claims_column`), not around it.
- **Accessibility shows claim ids.** Each node is an `NSAccessibilityElement` with identifier
  `^N`; ^2 appears at count > 0 and disappears after a reset.
- **Axiom audit.** `lake exe audit` walks every theorem in `Cairn.*` and `Examples.*` and fails
  on anything beyond `propext`, `Classical.choice` and `Quot.sound` (verified to catch a
  planted `sorry`).

## Numbers (M4 Max, release)

| Nodes | Lean layout + encode | Swift decode |
|---:|---:|---:|
| 100 | 0.05 ms | 0.002 ms |
| 1,000 | 0.40–0.48 ms | 0.013 ms |
| 10,000 | 3.7–3.9 ms | 0.09 ms |

Linear, about 0.38 µs per node, with no optimisation. 10k nodes is right at the 4 ms bar from
the design discussion, so performance is not the risk at M1's scale. The first Swift decoder
allocated per field and took 8.7 ms at 10k; loading in place fixed it.

## What we learned about the boundary

- **Exports can't borrow.** Lean 4.35 rejects `@&` on `@[export]` functions, so every argument
  is owned. Swift calls `cairn_lean_inc` on anything it keeps before passing it in.
- **Module initializers take no world argument** in 4.35: `initialize_cairn_Examples(builtin)`,
  and they call `lean_initialize_runtime_module` themselves.
- `lean_initialize_thread` and `lean_finalize_thread` exist in the runtime but aren't declared
  in `lean.h`; the shim declares them.
- `lean.h` defines `lean_object` as an anonymous struct, so the public header uses its own
  opaque `cairn_obj` and the shim casts. Swift sees `OpaquePointer`.
- Linking: Lake's static libs plus `libInit`, `libleanrt`, `libuv` and `libgmp`, merged with
  `libtool` into `build/lib/libcairn_lean.a`, then `-lc++`. No `libLean` (the compiler) needed.
- `NSAccessibilityElement`'s parent space is y-up even when the parent view is flipped.
- The render thread has to exist before the first viewport update, or quads land off screen.

## Not yet

Text (labels exist only in accessibility), real layout, claims as a language construct, the
frame format spec, IME, the debug socket, and conformance. Those are the next workstreams.
