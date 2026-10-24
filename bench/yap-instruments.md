# Yap on Cairn against the original Yap, under Instruments

Both apps measured by Apple's tools, not by Cairn's: `xcrun xctrace record` with Instruments'
own templates, the tables exported with `xctrace export` and summarised by scripts that only read
those tables. The apps emit `os_signpost`s (subsystem `dev.yap.bench`) at the moments the bench
drives (levels begin, each level buffer, key up, ready); Instruments timestamps them, and nothing
here comes from the apps' own timers. Each session's tables (`summary.md`) and one row per run
(`runs.csv`) are in [bench/yap-instruments/](yap-instruments/); every figure below is in one of
them. The harness is in `tools/bench/`.

**Headline (main at 340fecd, with #58's overlay):** at 60 Hz the two overlays now pace the same
(59.3 against 59.9 frames a second, time on glass σ 0.36 ms against 0.25 ms, level to glass
median 18.7 ms against 19.2 ms). The lag felt before #58 was real and was frame pacing: Cairn drew
only when a level arrived, 50 times a second, so on a 60 Hz display a fifth of its frames stayed
up for two refreshes (σ 6.9 ms against 0.25 ms). What is left: on the 120 Hz display Cairn draws
at 118 frames a second and its frames reach the glass 32 ms after they start, against the
original's 60 a second and 20 ms; it drops about 10 frames a run that the original doesn't; and
it used 2.5 times the original's CPU while recording, more than half of it redrawing the status
item. The fix for the status item is in this branch: it takes Cairn from 197 to 98 ms of CPU a
second, against the original's 82.

## Method

- **Code.** Cairn at 340fecd (main with #58) plus this branch's bench mode; `before-58/` at
  b9c2f47. The branch was then rebased onto df2d276 (#59 and #62: maps and how a file watch
  reports a change, not its 250 ms poll), which was not measured again.
- **Machine.** MacBook Pro Mac16,6, Apple M4 Max, 64 GB, macOS 27.0.1 (26A434), Xcode 27.1
  (27A9275), `xctrace version 27.1`. Displays (`NSScreen.maximumFramesPerSecond`): the Studio
  Display at 60 Hz (screen 0, main) and the built-in XDR at 120 Hz (screen 1, ProMotion).
- **Load.** The machine was shared with other agents' builds, an iOS Simulator and an antivirus
  scanner; the 1-minute load average at the start of each run is the `load1` column of each
  `runs.csv` (1.8 to 27.2, median 5.8). Order alternates per run (Cairn, original, original,
  Cairn, ...) so both apps see the same drift. CPU numbers move with the load more than anything
  else here (the original's overlay ranged from 40 to 82 ms/s between sessions); compare apps
  within a table, not across.
- **The apps.** `tools/bench/build-apps.sh` builds both into `build/bench/`, never touching
  `/Applications`:
  - `YapCairn.app`: `CairnYap` from this tree, release, ad hoc signed with `get-task-allow`.
  - `YapRef.app`: the original at 96ab494, cloned from `~/code/yap` (only read) to `/tmp/yap-ref`
    with `tools/bench/yap-ref.patch` applied, Release (like for like with Cairn's release
    build), signed the same way. `YapRef-Debug.app` is the Debug build people run from its
    Makefile; it was not measured.
- **What is fake, identically in both.** No real audio, hotkey, network or typing:
  - The microphone is a synthetic voice (the original's `Overlay.demo` level: syllables, a pause
    every 3.2 s) as 16 kHz samples, pushed in real time through each app's real input path:
    Cairn's `record` subscription and `receive`, the original's `AudioCapture` buffer handler.
    20 ms buffers, or 100 ms with `BUFFER_MS=100`.
  - The key is pressed by the bench thread just past each app's event monitor (Cairn's
    `KeySource`, the original's `Hotkey` callbacks).
  - OpenAI is a `URLProtocol` stub that answers at once with the next of three phrases.
  - Typing is a stub that emits the end signpost where the first key event would be posted, after
    each app's own checks (the target app exists and is in front).
- **What changed in the original** (`tools/bench/yap-ref.patch`, all behind `--bench-*`
  arguments): product name `YapRef`, bundle id `dev.yap.bench`, ad hoc signing; `YAP_BENCH_HOME`
  redirects its files; `App/Bench.swift` (the same driver, voice and stub as Cairn's
  `host/Sources/CairnYap/Bench.swift`); `AudioCapture` takes the bench's buffers instead of
  `AVAudioEngine`; `Yap.start` skips the accessibility prompt and the real hotkey; the Tink and
  Pop sounds are skipped; `TextInjector` emits the signpost instead of posting events; the
  overlay's screen can be chosen. Its drawing, timing and threads are untouched.
- **Commands.** `make bench-yap-overlay` (frame pacing only) or `make bench-yap` (everything);
  both run `tools/bench/build-apps.sh`, then `tools/bench/yap-instruments.sh SUITE...`, which for
  each run calls

  ```
  xcrun xctrace record --template TEMPLATE [--instrument os_signpost] --time-limit Ns --no-prompt \
      --target-stdout - --env YAP_BENCH_HOME=$(mktemp -d) --launch -- BUNDLE/Contents/MacOS/BIN ARGS
  ```

  then `tools/bench/analyze.py SUITE TRACE` (one JSON per run, with the per-frame samples) and
  `tools/bench/report.py` (the tables below). Traces are deleted after summarising. Run 0 of each
  app is a warm-up and is left out; runs where Instruments started recording after the levels
  began, or saw no frames presented, are excluded. `runs.csv` lists every run with its status
  (warm-up, included or excluded and why) and the load average when it started.
- **Data.** Only `summary.md` and `runs.csv` are committed. Distributions in `summary.md` (frame
  intervals, level to glass, key up to typed) are pooled over the frames or trials of the
  included runs; `runs.csv` has each run's own percentiles. The per-run JSON, with every frame,
  is written to `bench/out/yap-instruments/<tag>/<suite>/<app>-<run>.json` (gitignored) by
  `make bench-yap` or `tools/bench/yap-instruments.sh`; `tools/bench/report.py
  bench/out/yap-instruments/<tag>` rebuilds `summary.md` and `runs.csv` from it.

| suite | template | app arguments | measured window | runs |
|---|---|---|---|---|
| overlay | Metal System Trace + os_signpost | `--bench-overlay --seconds 20 --screen S --buffer-ms B` | levels begin + 2 s to levels end (18 s) | 5 + warm-up |
| hitches | Animation Hitches + os_signpost | `--bench-overlay --seconds 8` | 6 s | 3 + warm-up |
| latency | Logging | `--bench-latency --trials 21` | trials 2 to 21 | 5 + warm-up |
| idle | Activity Monitor | `--bench-idle`, 120 s | after the first 20 s | 3 + warm-up |
| menu | Activity Monitor + os_signpost | `--bench-menu` (opens its own status menu), 60 s | after the first 8 s | 3 + warm-up |
| launch | App Launch + os_signpost | `--bench-idle`, 10 s | process start to `ready` | 5 + warm-up |
| profile | Time Profiler + os_signpost | `--bench-overlay --seconds 10` | levels begin + 2 s to end | 3 + warm-up |

What each number is, and the Instruments table it comes from:

- **frames/s, frame interval:** `ca-client-presented-handler`, Core Animation's presented
  event for each of the app's drawables, inside the window. Interval: median / p90 / p99 / max,
  pooled over runs.
- **frames held long:** intervals over 1.5 times the app's own median interval.
- **cadence changes:** consecutive intervals that differ by more than half a display refresh,
  i.e. uneven motion even when nothing is "late".
- **level to present call:** each `level` signpost (a buffer pushed into the app) to the app's
  next `-[CAMetalDrawable present]` (`com.apple.coreanimation` `ClientDrawable` end).
- **level to glass:** the same level to the next presented drawable after that call. With three
  drawables queued it can be one frame early; FramePacing's end to end below is the exact figure.
- **fp.\*:** `com.apple.FramePacing`'s own per-second statistics for each `CAMetalLayer`,
  averaged over the window's seconds:
  - `PresentedFrameStats`: time on glass, total end to end (frame start to on glass), GPU done to
    completed, next drawable wait.
  - `LateOnGlassPresentStats` and `SkippedFrameStats` frame counts, summed per run.
- **CPU ms/s:** in the overlay suite, the Metal System Trace's 1 ms `time-sample`s in state
  Running, per thread; in the profile suite, Time Profiler's weighted samples, with stacks.
- **hitches:** the `hitches` table. **idle and menu:** `sysmon-process` (cumulative CPU,
  interrupt wakeups, physical footprint). **launch:** `life-cycle-period` and the `ready`
  signpost (the app is watching its key).

- **Disk.** xctrace leaves a raw `instruments*.ktrace` (10–30 GB for a Metal System Trace) in
  the per-user temp directory (`getconf DARWIN_USER_TEMP_DIR`; setting `TMPDIR` doesn't move
  it) and never deletes it, and a `DTServiceHub` it starts can hold the file open for a minute
  after it exits. Since the 120 Hz follow-up below, `tools/bench/yap-instruments.sh` notes, every
  second while it records, the ktrace files that its own xctrace's descendants hold open, and
  once the trace is saved deletes those that are also newer than a marker touched just before
  the run, and stops those helpers; a trace whose analysis fails is deleted too unless `KEEP=1`.
  Files other recordings made are never touched. Before each run it checks that the temp,
  trace and output volumes have 60 GB free (`MIN_FREE_GB`) and stops with a message if not.

What isn't measured: the real microphone, the network and transcription, and how the real
key's event reaches each app. Power Profiler was tried and is not available: xctrace 27.1 reports "The Power Profiler instrument is not supported on macOS".

## Overlay while listening, hands free (main, with #58)

60 Hz display, 20 ms buffers (`main/screen0-buf20`):

| | Cairn | original |
|---|---:|---:|
| runs | 5 | 4 (1 excluded: no frames presented) |
| frames/s | 59.34 (59.28–59.35) | 59.91 (59.74–59.97) |
| frame interval ms, median / p90 / p99 / max | 16.67 / 16.73 / 16.87 / 66.9 | 16.67 / 16.75 / 16.85 / 33.5 |
| frames held long | 0.58% | 0.21% |
| cadence changes | 1.2% | 0.4% |
| level to present call ms, median / p90 / p99 / max | 8.3 / 15.0 / 16.6 / 30.0 | 8.2 / 15.0 / 16.8 / 27.9 |
| level to glass ms, median / p90 / p99 / max | 18.7 / 30.3 / 33.3 / 79.3 | 19.2 / 29.6 / 32.7 / 43.9 |
| fp time on glass avg / σ ms | 16.71 / 0.36 | 16.70 / 0.25 |
| fp total end to end avg ms | 47.9 | 48.6 |
| fp next drawable wait avg / max ms | 5.7 / 32.9 | 3.8 / 16.2 |
| fp skipped frames per run | 10 (9–11) | 0 |
| fp late on glass per run | 660 (3–953) | 1018 (2–1075) |
| CPU ms/s | 205 (165–267) | 82 (75–90) |
| CPU ms/s: main / unnamed workers / render / Lean | 132 / 38 / 24 / 18 | 48 / 32 / – / – |
| hitches (Animation Hitches, 3 runs) | 0 | 0 |

120 Hz display, 20 ms buffers (`main/screen1-buf20`):

| | Cairn | original |
|---|---:|---:|
| runs | 4 (1 excluded: recording started late) | 5 |
| frames/s | 117.8 (105.7–118.9) | 60.0 (59.96–60.05) |
| frame interval ms, median / p90 / p99 / max | 8.34 / 8.41 / 16.68 / 41.7 | 16.67 / 16.72 / 24.98 / 41.8 |
| cadence changes | 6.6% | 4.3% |
| level to glass ms, median / p90 / p99 / max | 11.2 / 15.5 / 28.7 / 47.6 | 12.3 / 19.1 / 24.5 / 43.8 |
| fp time on glass avg / σ ms | 8.44 / 0.82 | 16.67 / 0.53 |
| fp total end to end avg ms | 32.0 | 20.3 |
| fp next drawable wait avg / max ms | 6.1 / 29.4 | 0.009 / 0.12 |
| fp skipped frames per run | 13 | 0 |
| fp late on glass per run | 2080 | 935 |
| CPU ms/s | 225 (118–270) | 72 (33–77) |

60 Hz, 100 ms buffers (`main/screen0-buf100`; what a microphone delivering 100 ms buffers would
look like; the real buffer size was not measured): both pace as with 20 ms buffers (59.3 against
59.9 frames/s, σ 0.35 against 0.37 ms), and CPU is level, 61 against 57 ms/s. So Cairn's extra
CPU with 20 ms buffers is a cost per level event.

## Before the overlay match (#58)

The same suites at b9c2f47, Cairn's earlier overlay: 120 bars, one bar per 20 ms level window,
drawn only when a level arrived (`before-58/`).

| | Cairn 60 Hz | original 60 Hz | Cairn 120 Hz | original 120 Hz | Cairn 60 Hz, 100 ms buffers |
|---|---:|---:|---:|---:|---:|
| frames/s | 48.7 | 59.9 | 52.1 | 60.0 | 12.5 |
| frame interval ms, median / p90 / p99 | 16.7 / 33.3 / 33.4 | 16.7 / 16.7 / 16.8 | 16.7 / 25.1 / 33.4 | 16.7 / 16.7 / 16.8 | 99.8 / 100.1 / 116.7 |
| frames held long | 21.9% | 0.26% | 14.3% | 0.12% | 0.09% |
| cadence changes | 38.9% | 0.5% | 73.8% | 0.8% | 62.4% |
| fp time on glass avg / σ ms | 20.3 / 6.9 | 16.7 / 0.25 | 19.0 / 6.6 | 16.7 / 0.28 | 79.8 / 26.0 |
| fp total end to end avg ms | 34.4 | 48.4 | 24.4 | 20.4 | 33.3 |
| level to glass ms, median / p99 | 11.7 / 48.7 | 20.1 / 32.8 | 13.0 / 33.8 | 11.8 / 20.8 | 42.3 / 55.9 |
| CPU ms/s | 110 | 40 | 161 | 37 | 44 |

Cairn's frames got to the glass sooner than the original's (34 against 48 ms end to end at 60
Hz), but at the rate the levels came: 50 Hz sampled by a 60 Hz display shows four frames for one
refresh and one for two, about ten times a second; on 120 Hz it alternates 16.7, 25 and 33 ms.
The original draws every refresh at 60 frames a second and decays the level between buffers, so
it moves evenly even with 100 ms buffers.

## Key up to typed, idle, menu, launch (main)

| | Cairn | original |
|---|---:|---:|
| key up to typed ms (stubbed), median / p90 / p99 / max | 6.3 / 11.0 / 13.2 / 13.2 (n=100) | 4.6 / 19.8 / 22.7 / 22.7 (n=83) |
| idle in the menu bar: CPU | 0.21% (2.1 ms/s) | 0.012% |
| idle: wakeups/s | 6.5 | 0.48 |
| idle: physical footprint | 16.3 MB | 17.6 MB |
| idle: threads | 8 | 4 |
| menu open: CPU / wakeups/s | 0.04% / 4.4 | 0.002% / 0.17 |
| menu open: footprint | 21.3 MB | 22.5 MB |
| launch: process start to didFinishLaunching ms | 47.6 (46.5–54.0) | 70.5 (66.1–82.5) |
| launch: process start to ready ms | 61.0 (58.9–74.0) | 91.6 (84.8–111.8) |

- **Key up to typed.** Measured from the key up at each app's key callback to where it would
  post the first key event, with transcription answered at once by the stub. Both are a few
  milliseconds; each run's median moved between 2 and 9 ms (Cairn) and 4 and 17 ms (the
  original) with the machine's load. Two of the original's runs ran past the trace's time limit
  and lost their last trials (83 of 100); the limit is longer now. This is not where a lag would
  be felt.
- **Idle.** Cairn wakes 13 times as often and uses about 17 times the CPU, though both are small:
  2 ms a second against 0.1. Its world polls the config and dictionary files every 250 ms and
  the clock every 2 s; the original checks its config every 2 s.
- **Menu open.** Both use less CPU with the menu open than closed; why was not traced. The
  original's process samples cover only the first 24 s of the window; its numbers are from those.
- **Launch.** Cairn reaches `applicationDidFinishLaunching` and `ready` about 30 ms sooner.

## Where the time goes (Time Profiler, main)

Three 10 s overlay runs per app at 60 Hz, alternating main's build (`main`, 340fecd without the
fix), this branch (`fixed`) and the original (`main/profile/`). CPU per second in the window,
median of the runs (range in `summary.md`, each run in `runs.csv`). The named functions are
inclusive (they count their callees), so they overlap and don't add up.

| ms/s | main | fixed | original |
|---|---:|---:|---:|
| total | 342 (341–380) | 115 (114–117) | 102 (68–117) |
| main thread | 230 | 13 | 55 |
| `-[NSStatusItem _updateReplicants]` | 75 | 0 | – |
| `CA::Transaction::commit()` | 93 | 0.1 | 33 |
| `HostView.applyLatestFrame()` | 31 | 10 | – |
| `StatusHost.update(_:)` | 28 | 9 | – |
| render thread (`RenderLoop.tick` 27 / 23) | 28 | 23 | – |
| Lean thread (`LeanCore.step` 19 / 15) | 26 | 23 | – |
| other threads | 66 | 56 | 47 |
| `ShapeCache.paintShadow` (vImage blur 1.7 / 2.3) | 4.1 | 5.6 | – |

- **main:** most of the main thread is the status item. `_updateReplicants` redraws the menu
  bar's copies of the status button (`NSStatusBarButtonCell drawWithFrame`, `NSImage` symbol
  drawing, layout), and Core Animation commits 93 ms/s. `HostView.applyLatestFrame` runs
  `StatusHost.update` on every frame, even at 50 a second, which sets the button's
  `imagePosition`, accessibility label and identifier to the same values; each write makes
  AppKit redraw the replicants.
- **fixed:** the replicant redraws and the commits are gone and the main thread drops to
  13 ms/s, under the original's 55. What is left is the render and Lean threads (about 23 ms/s
  each) and dispatch workers.
- **The original:** main thread 55 ms/s, about 33 of it Core Animation commits.

The CPU level moves between sessions (an earlier single-run Time Profiler session had main's
build at 173 to 223 ms/s), so compare within this table. The self-test bench in
[bench/yap.md](yap.md) measures surface apply at 0.2 ms with the surfaces detached, so it never
saw the status item's redraw.

## The fix measured: status item writes only on change

`StatusHost.update` (host/Sources/CairnHost/Surfaces.swift) now writes `isVisible`,
`imagePosition`, the accessibility label and the identifier only when they differ. A/B against
main's build, alternating, 60 Hz, 20 ms buffers (`fix-status/screen0`, Metal System Trace;
1 run of main's build excluded: recording started late):

| | before (main) | after |
|---|---:|---:|
| CPU ms/s | 197 (117–257) | 98 (56–106) |
| main thread ms/s | 128 | 12 |
| Time Profiler, CPU ms/s (`main/profile`) | 342 | 115 |
| Time Profiler, main thread ms/s | 230 | 13 |
| frames/s | 59.28 | 59.28 |
| fp time on glass σ ms | 0.48 | 0.51 |
| level to glass ms, median / p99 | 23.6 / 39.5 | 24.3 / 40.4 |

Pacing is unchanged. Under the Metal System Trace the CPU halves and is near the original's
(82 ms/s in the main run); under Time Profiler it falls to a third, 115 against the original's
102 in the same session.

## Likely causes, with evidence

1. **The felt lag before #58 was frame pacing, not latency.** Cairn's frames got to the glass
   sooner than the original's, but only when a level arrived. 50 Hz on 60 Hz gave σ 6.9 ms time
   on glass and 39% cadence changes, against 0.25 ms and 0.5%. On 120 Hz it was 74% cadence
   changes. #58's tape is drawn every display tick from the level history and the clock, and the
   difference is gone at 60 Hz.
2. **120 Hz: Cairn draws twice as often as the original and queues frames.**
   - The panel's render loop redraws a frame with a `paint` draw on every display-link tick, so
     118 frames/s on ProMotion. The original's MTKView is fixed at `preferredFramesPerSecond = 60`.
   - Cairn waits 6 ms on average (up to 29 ms) for the next drawable, and its frames take 32 ms
     from start to glass against the original's 20 ms. It renders as fast as the display runs,
     the queue of three drawables fills, and each frame waits behind the others.
   - The tape's history is defined per 60 Hz frame (`YapTape.frameMs`), so the extra frames add
     little the eye can use.
3. **Skipped frames.** Cairn skips 9 to 13 frames a run (fp `SkippedFrameStats`) and its worst
   interval is 67 to 83 ms, against 0 and 33 ms. They are rare (under 1% of intervals); which frames they are was not traced. No hitches in
   Animation Hitches for either app.
4. **No drawable starvation at 60 Hz.** Both apps wait for drawables at times (Cairn 5.7 ms
   average, the original 3.8 ms) and both run about 48 ms end to end, three refreshes. That is
   the triple-buffered queue of both, not a Cairn problem.
5. **Main-thread hops are not on the frame's path.** The panel renders on its own thread from
   the engine's latest frame, and level to present call is the same in both apps (median 8.3 ms
   against 8.2 ms). The main thread's time was the status item (fixed here), not the overlay.

## Recommendations

1. Merge the status item fix (this branch). It halves Cairn's CPU while recording at no cost to
   pacing.
2. Cap the panel's display link at 60 Hz when its frame has a `paint` draw
   (`CADisplayLink.preferredFrameRateRange`), or let the painter declare its rate. That would
   match the original on ProMotion and should cut the 120 Hz end to end from 32 ms toward 20 ms.
   It needs its own before and after under this harness.
3. Shadows are rasterised again while recording (`ShapeCache.paintShadow`, 4 to 6 ms/s, 2 of
   it vImage blur, in `main/profile`; an earlier single run showed 15). Small now; if it grows,
   find which shadowed shape gets a new cache key per frame. A fading shadow colour would do it.
4. Idle: watch the config and dictionary with a file system event source instead of polling
   every 250 ms (6.5 wakeups/s against 0.5).
5. Measure the real microphone's buffer size once on this machine. With 100 ms buffers the new
   tape still paces evenly, so it matters less now; with the old one it was 12.5 frames/s.

To rerun on another branch: `make bench-yap-overlay` (about 15 minutes, needs a free 60 Hz
display as screen 0; `SCREEN=1` for the built-in display), or `make bench-yap` for everything
(about 2.5 hours). Results land in `bench/out/yap-instruments/<tag>/` (`summary.md`, `runs.csv`
and the per-run JSON); copy `summary.md` and `runs.csv` into `bench/yap-instruments/` to commit
them.

## Follow-up: 120 Hz at 60 frames a second, and the file watch

Two of the recommendations above, matched to what the original does (lane `yap-perf2`).

**What the original does.**

- **Pacing.** The waveform is an `MTKView` with `preferredFramesPerSecond = 60`
  (`~/code/yap/App/Overlay.swift` L352), paused while not recording (L313–314, L353); it draws
  on its `CVDisplayLink` thread's callback. The rest of the overlay is SwiftUI: the clock is a
  `TimelineView(.periodic(from: .now, by: 0.25))` (L226) and the text eases with
  `.animation(.easeOut(duration: 0.15), value: model.text)` (L256). On the 120 Hz display it
  presents 60.0 frames a second (above, and again below).
- **Files.** No file system events and no dispatch source: `watchConfig` polls `config.json`'s
  modification date with `FileManager.attributesOfItem` every 2 s in a `Task` loop and reloads
  when it differs (`~/code/yap/App/Yap.swift` L206–225; its comment: "A file watch would miss
  editors that save in place, and a stat every two seconds costs nothing"). The dictionary is
  not watched: `DictationDictionary.load()` reads it at each send (L326) and each live preview
  (L385).

**The changes.**

- The panel's display link is capped at 60 Hz (`CAFrameRateRange(minimum: 60, maximum: 60,
  preferred: 60)`, `PanelContentView.maxFps`, host/Sources/CairnHost/Surfaces.swift and
  RenderLoop.swift). Windows keep the display's rate.
- `watchFile` looks every 2 s (`World.watchPeriodMs`, was 250 ms), as the original polls, and
  50 ms after a look that saw the file move (`World.watchSettleMs`), reporting once it holds
  still. An edit is heard 0.05–2.05 s after the save, against the original's 0–2 s
  (docs/effects.md, docs/yap-parity.md). The trusted fuzz now also varies the second look
  (^963 `subs.watch-file`).

**120 Hz display** (`perf2/120hz-buf20`: built-in XDR as screen 0, the Studio Display was
disconnected; 20 ms buffers; `cairnbase` is main at a83d447, `cairn` this branch with the cap
only; Metal System Trace; 1-minute load 4.3 to 39.9, median 9.9; 1 `cairnbase` run excluded,
recording started late):

| | main (a83d447) | 60 Hz cap | original |
|---|---:|---:|---:|
| runs | 4 | 5 | 5 |
| frames/s | 118.3 (117.4–119.0) | 59.75 (59.71–59.82) | 59.97 (59.94–60.04) |
| frame interval ms, median / p90 / p99 / max | 8.33 / 8.38 / 12.5 / 41.7 | 16.67 / 16.74 / 25.1 / 41.7 | 16.67 / 16.72 / 16.82 / 33.3 |
| frames held long | 1.0% | 3.7% | 0.24% |
| cadence changes | 2.0% | 16.0% | 1.7% |
| level to glass ms, median / p90 / p99 / max | 11.8 / 15.2 / 26.8 / 39.3 | 16.9 / 24.1 / 37.7 / 50.6 | 11.3 / 17.7 / 20.2 / 43.8 |
| fp time on glass avg / σ ms | 8.40 / 0.55 | 16.67 / 1.36 | 16.67 / 0.47 |
| fp total end to end avg ms | 32.7 | 24.8 | 20.0 |
| fp next drawable wait avg / max ms | 7.5 / 27.9 | 0.010 / 0.94 | 0.005 / 0.023 |
| fp skipped frames per run | 12.5 | 4 | 0 |
| fp late on glass per run | 2011 | 859 | 688 |
| CPU ms/s | 70 (60–79) | 50 (40–61) | 65 (61–71) |

- The cap does what it should: 60 frames a second, no wait for drawables (7.5 ms → 0.01 ms),
  end to end 32.7 → 24.8 ms (the original 20.0), CPU down by a quarter, skipped frames 12.5 → 4.
- What it leaves: **phase slips.** About one interval in 50 (and one in 5 in two of the five
  runs) is a 25 ms frame followed by an 8.3 ms one, where the original has about one in 200.
  The 60 Hz callback lands close enough to a refresh that a frame sometimes misses it and the
  next catches up. Level to glass is 5 ms later than the original's at the median.
- **Tried and not kept: `present(afterMinimumDuration: 1/60)`** (`perf2/120hz-mindur`, 3 runs
  each; there `cairn` is the cap plus the minimum duration and `cairnbase` the cap alone).
  The slips go (cadence changes 0.9% against the cap's 4.9% and the original's 1.3%; time on
  glass σ 0.06 ms) but frames queue: end to end 43.9 ms against 24.9 and 19.5, level to glass
  median 20.2 against 16.5 and 11.0, and 9 skipped frames a run. It is not in the branch.

**Not measured yet** (the session ended for the weekend; see the PR): the idle suite before
and after the 2 s watch (B: 6.5 wakeups/s and 0.21% CPU against the original's 0.48 and
0.012%; at 2 s the two watches should wake about 0.5 times a second instead of 8, beside the
2 s permission checks), a 60 Hz check of the cap (no 60 Hz display was connected), and recording
CPU at 60 Hz.
