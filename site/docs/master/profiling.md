---
title: Profiling against a reference
nav: Profiling against a reference
eyebrow: Master
lede: How Cairn measured its port of Yap against the original, with Apple's own tools so the harness can't flatter the result.
---

"It feels laggy" is a claim too, and Cairn treats it like one: it needs numbers. When an app is a
port of an existing one, the fairest numbers compare the two under the same conditions, measured
by tools neither of them controls. This page describes how Cairn did that for Yap, a dictation app
it ports [one to one](/docs/examples/yap/), and how to do the same for your own app.

## The rule: measure with Apple's tools

Both apps run under `xcrun xctrace record`, the command-line side of Instruments, with
Instruments' own templates. The tables are exported with `xctrace export` and summarised by
scripts that only read those tables. Each app marks the moments that matter with `os_signpost`
(a level arrived, key up, ready, typed), and Instruments timestamps them. No number comes from an
app's own timers.

## Make the comparison fair

- **Build both the same way.** Release builds, ad hoc signed with `get-task-allow` so
  Instruments can attach, built into a scratch folder, never `/Applications`. The reference app
  is copied and patched in a temporary folder; its own repository is only read.
- **Fake the outside world identically.** The same synthetic voice is pushed through each app's
  real audio path, in real time. The hot key is pressed just past each app's own event monitor.
  The network is a stub that answers at once, and typing is a stub that emits a signpost where
  the first key would be posted. Drawing, timing and threads stay real.
- **Alternate the apps run by run** (A, B, B, A, …) so both see the same drift, discard a warm-up
  run of each, and record the load average at the start of every run. On a shared machine CPU
  numbers move with the load more than with the code, so compare apps within one table only.
- **Exclude bad runs openly.** A run where recording started after the signposts began, or where
  no frames were presented, is excluded and listed with its reason, never dropped silently.

## Which template answers which question

| Question | Template | What to read |
|---|---|---|
| Frame pacing and frames on glass | Metal System Trace | the presented-drawable table, and Core Animation's per-second frame pacing statistics: time on glass, end to end, late and skipped frames |
| Hitches | Animation Hitches | the hitches table |
| Where the CPU goes | Time Profiler | weighted samples with stacks |
| Idle CPU, wake-ups, memory | Activity Monitor | per-process system monitor samples |
| Launch time | App Launch | the launch period, plus your own `ready` signpost |

Power Profiler isn't available from `xctrace` on macOS.

## Running it

Two make targets build both apps and run the suites:

<!-- include Makefile#make-bench-yap -->

The script runs one suite per template, each with the arguments that put the apps in the right
state:

<!-- include tools/bench/yap-instruments.sh#bench-suites -->

For each run it calls `xctrace record` with the suite's template, the `os_signpost` instrument, a
time limit, `--no-prompt` and `--launch` followed by the app's binary and its bench arguments, so
Instruments starts the app and records only that process. It then summarises the trace and
deletes it. Only per-run summaries and one CSV row per run are kept: per-frame data for 144 runs
came to 2.8 MB, too much for a diff.

## What it found

The lag a person felt in Cairn's Yap was **frame pacing**, not latency. The overlay drew only when
a new audio level arrived, 50 times a second, so on a 60 Hz display a fifth of its frames stayed
up for two refreshes. Its latency was no worse than the original's. Two lessons generalise:

- Look at the spread of frame intervals and how often the cadence changes, not only frames per
  second.
- On a ProMotion display, a Metal layer with no frame-rate cap runs at 120 Hz and queues on
  drawables. Capping it at 60, as the original does, brought frames to the glass sooner.

Time Profiler then showed that most of the remaining CPU went to AppKit redrawing the menu bar,
because the host wrote unchanged status item properties every frame. Writing only what changed
halved it.

## Mind the disk

Every `xctrace` recording leaves a raw `instruments*.ktrace` file of 10 to 30 GB in the per-user
temporary directory (`getconf DARWIN_USER_TEMP_DIR`; setting `TMPDIR` doesn't move it), and
nothing deletes it, even after the `.trace` bundle is gone. One night of runs filled 336 GB. A
helper process can hold the file open for a minute after `xctrace` exits.

Cairn's script handles this: before each run it checks that 60 GB are free and stops if not, and
after each run it deletes exactly the ktrace files its own recording created. If you write your
own harness, do the same.
