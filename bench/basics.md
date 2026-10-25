# Basics: input → frame, 10 and 1,000 items

A record from when Basics was in this repository. Basics and its bench are in
iamnbutler/cairn_examples now; Cairn's own input → frame bench is the fixture's (`make bench`,
which runs `cairn bench` on test/fixture).

`make bench` ran `CairnBasics --bench` (release, `LEAN_ABORT_ON_NONLINEAR=1`): the app's real
exports and the v1 codec with no threads, so each sample is encode events (Swift) →
`cairn_app_step` (route, `machine.update`, view, layout with Core Text metrics, settle) →
`cairn_app_frame` (`Frame.ofLaid`, encode) → decode (Swift). It clicks the field, adds `n` items
by typing "Item i" and Enter, then times 50 samples (after 10 warm-up) of each input. Three
runs, Apple M4 Max, macOS 27, 2026-10-23, load average 7–11 from other agents' builds.

| Items | Frame | Draws | AX nodes | Type one character | Click a checkbox (move, down, up) | Pointer move |
|---:|---:|---:|---:|---:|---:|---:|
| 10 | 4,633 B | 62 | 45 | p50 0.14–0.15 ms, p95 0.19–0.22 ms | p50 0.27–0.28 ms, p95 0.28–0.60 ms | p50 0.022–0.024 ms |
| 1,000 | 399,295 B | 5,012 | 4,005 | p50 7.3–7.6 ms, p95 7.7–8.0 ms | p50 14.5–14.7 ms, p95 15.0–15.2 ms | p50 1.8–1.9 ms |

Adding the items one Enter at a time took 1.2–1.3 ms for 10 and 6.0–6.1 s for 1,000 (quadratic:
each add re-lays-out the whole list).

Reading:

- **10 items is well inside a frame**: a keystroke is 0.15 ms end to end, a click 0.3 ms.
- **1,000 items is linear and too slow for 120 Hz** (8.3 ms budget for everything): every change
  re-runs `view` and `layout` over all 1,000 rows and re-encodes a 400 KB frame. A click is two
  of those (the press on down, the toggle on up), so twice a keystroke. A pointer move that
  changes nothing skips the update and relayout, leaving hit testing and the frame encode
  (~1.9 ms, close to `bench/frame.md`'s encode cost for 4,000 nodes).
- **About 400 bytes and 5 draws per item** (row background, checkbox, label, delete button and
  its text, plus ~4 AX nodes with labels).
- What would fix 1,000: a scroll container that lays out only visible rows, and reusing the
  previous frame's encoding for unchanged subtrees. Neither exists yet; the window shows the
  first ~13 rows and the rest overflow, clipped.
