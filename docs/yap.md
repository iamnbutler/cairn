# Yap on Cairn

M2 step 3 (GOAL.md): Yap, the push-to-talk dictation app at `~/code/yap`, as a Cairn app. Its
state is the dictation machine's (`lean/Examples/Yap/Model.lean`) plus what the app keeps
around it (`AppState`, `lean/Examples/Yap/App.lean`); the menu bar item and the overlay are
Lean views (`View.lean`); the claims (^301–^347, `lean/Examples/Yap.lean`) are stated over the
app machine and proved through its `receive` (`AppProofs.lean`). The Swift side
(`host/Sources/CairnYap/main.swift`) only builds the world: the real microphone, keyboard,
typing and network, or fakes for the self test.

It is a drop-in for the original: the same files, the same model, the same key.

| | Original Yap | Yap (Cairn) |
|---|---|---|
| App | `/Applications/Yap.app`, `dev.yap.Yap` | `/Applications/Yap (Cairn).app`, `dev.yap.cairn` |
| Files | `~/Library/Application Support/yap/`: `secrets.env`, `dictionary.txt`, `config.json`, `transcripts/YYYY-MM-DD.jsonl` | the same files |
| Model | `defaults read dev.yap.Yap model`, default `gpt-transcribe` | read from the same place, as each recording starts |
| Dictate with key, Press Return | its `UserDefaults` | read from the original's defaults at first launch, then kept in `~/Library/Application Support/Cairn/Yap/prefs.json` (it never writes the original's defaults) |

## Build and install

```sh
make yap            # build/apps/Yap (Cairn).app: release build, signed
make yap-install    # copies it to /Applications/Yap (Cairn).app (never touches Yap.app)
open "/Applications/Yap (Cairn).app"
```

`make yap` signs with the first valid "Apple Development" identity in the keychain
(`security find-identity -v -p codesigning`), with the hardened runtime and the
`com.apple.security.device.audio-input` entitlement (`host/Bundles/Yap/`). The bundle is an
accessory app (`LSUIElement`: no Dock icon, no ⌘Tab) with a microphone usage description. Pass
`YAP_SIGN=<identity or hash>` to pick another identity. Signing with the same identity every time
matters: macOS grants Accessibility and the microphone to the code signature, so an ad hoc or
differently signed build is a new app to TCC and has to be granted again.

Check a build with `codesign --verify --strict --verbose=2 "build/apps/Yap (Cairn).app"` and
`codesign -d --entitlements - "build/apps/Yap (Cairn).app"`.

## Permissions

Both are granted to "Yap (Cairn)" separately from the original Yap.

- **Accessibility** (the global key, and typing into other apps). Until it is granted the menu
  shows "Accessibility Is Off: Grant It…", which opens System Settings › Privacy & Security ›
  Accessibility. Add or enable "Yap (Cairn)" there. The app checks again every 2 s and when
  the menu opens; no relaunch is needed.
- **Microphone.** macOS asks the first time a recording starts. If it was refused, the menu
  shows "Microphone Is Off: Grant It…", which asks again or opens System Settings ›
  Privacy & Security › Microphone.
- **The API key** is the original's `OPENAI_API_KEY` in `secrets.env` (or the environment
  variable). The host reads it when it sends a request; it never reaches Lean, a frame or a log.

## Switching from the original Yap, and back

Both apps listen for the same key, so only one may hold it. Yap (Cairn) checks every 2 s, and
when its menu opens, whether `dev.yap.Yap` is running. While it is, Yap (Cairn) doesn't watch
the key at all, and its menu says "Yap is running. Quit it to dictate with Right Command here."
This is claim ^346, proved (`leave_original`) and fuzzed.

1. Quit the original Yap (its menu › Quit).
2. Open Yap (Cairn). Within 2 s the status line in its menu goes, and it is listening.
3. To go back: quit Yap (Cairn) (⌘Q in its menu) and open Yap.app. Nothing needs undoing:
   the transcripts, dictionary and config are shared, and Yap (Cairn) never writes the
   original's defaults.

If both are open, the original has the key; Yap (Cairn) waits. Remove Yap (Cairn) with
`rm -rf "/Applications/Yap (Cairn).app"` (and, optionally,
`~/Library/Application Support/Cairn/Yap/`).

## What it shows

- **The menu** (^301), in Yap's order: the status line; status lines for the original Yap
  running, missing Accessibility or Microphone, and errors; Copy Last Transcript; Recent
  Transcripts ▸ (up to five, ⚠︎ on any that never reached its app, then Open Transcripts
  Folder); Dictate with ‹key› ✓, Press Return After Dictating ✓, Keep Transcripts (N Days) ✓;
  Edit Dictionary…, Edit Settings…; Quit Yap (Cairn) (⌘Q). The icon follows the phase
  (`waveform`, `mic.fill`, `text.bubble`).
- **The overlay** (^399; ^345 is retired), at the bottom of the screen, never taking focus
  or clicks, drawn as the original's (see "Overlay parity" below): the phase (REC, REC · HANDS
  FREE · TAP AGAIN TO SEND, TRANSCRIBING, TYPED, NOT TYPED · IN RECENT TRANSCRIPTS) with a
  glowing dot and a clock that stops when recording does; the tape (the original's
  `Overlay.metal`, unchanged: the scope, the scrolling ruler, the reel and the meter, from the
  microphone's levels and the preview's cuts); and the live transcript's last 280 characters.
  It hides 1.5 s after a transcript is typed and 4 s after one fails. `"overlay": false` in
  config.json turns it off.

## Overlay parity

The overlay is the original's `OverlayView` rebuilt in Cairn: the same palette, fonts (SF Pro,
expanded width, tracking, tabular digits), padding, gaps, continuous corners, edge and shadows,
and the original's `Overlay.metal`, unchanged, as a host-drawn `paint` node (^1004 assumes it
paints only inside its box). It is checked against the original, not by eye but pixel by pixel:
`tools/overlay-parity` captures the original's own panel (a patched copy that injects the tape's
values; it never records, listens to keys or types) and renders Cairn's from the same states,
both at 2x.

**Stills.** Twelve states: each phase without text and with two lines, and 300 characters (the
tail with "…") listening and typed. Each image below is the original | Cairn | the difference ×
4. Channels more than 8 levels (of 255) apart, by region:

| state | window | tape | text | header | whole window |
|---|---|---:|---:|---:|---:|
| listening, no text | 556 × 156 both | 0 (max 2) | – | 1.3% | 0.24% |
| listening, two lines | 556 × 214 both | 0 (max 3) | 0 (max 2) | 1.3% | 0.18% |
| hands free, no text | 556 × 156 both | 0 | – | 6.0% | 0.92% |
| hands free, two lines | 556 × 214 both | 0 | 0 | 6.0% | 0.67% |
| transcribing, no text | 556 × 156 both | 0 | – | 2.9% | 0.47% |
| transcribing, two lines | 556 × 214 both | 0 | 0 | 2.9% | 0.34% |
| typed, no text | 556 × 156 both | 0 | – | 1.5% | 0.27% |
| typed, two lines | 556 × 214 both | 0 | 0 | 1.5% | 0.20% |
| failed, no text | 556 × 156 both | 0 | – | 5.6% | 0.87% |
| failed, two lines | 556 × 214 both | 0 | 0 | 5.6% | 0.63% |
| listening, 300 characters | 556 × 254 both | 0 | 0 (max 2) | 1.3% | 0.15% |
| typed, 300 characters | 556 × 254 both | 0 | 0 (max 3) | 1.5% | 0.17% |

Images: `docs/yap-overlay/<state>.png` (`listening-empty.png`, `listening-two-line.png`, …,
`typed-300.png`).

**Motion.** The original captured at 60 Hz while the text appears, grows to two lines, is typed
and hides; Cairn rendered at the same frame times (`docs/yap-overlay/motion-appear.png`,
`motion-grow.png`: the original on the left). The original eases the panel with SwiftUI's
`easeOut` over 0.15 s, starting one frame after the window takes its new height; new text fades
in where it ends up and the old fades out as it moves. Cairn does the same in Lean
(`easingView`, `textEaseMs`, `textEaseDelayMs`), and its header sits within 1.7 px of the
original's in every frame of both changes (one point of integer layout is 2 px). The fade on
hide is the same call in both (`NSAnimationContext`, 0.18 s, `alphaValue`). The clock redraws
every 0.25 s in both, as `TimelineView(.periodic(by: 0.25))` does.

**What still differs, and why:**

- **The dot and the label sit 1 px (half a point) higher.** The original centres a 7-point dot
  and a 10-point label in a 26-point row, at 9.5 points and a baseline of 16.55; Cairn's layout
  and frames are in whole points (AGENTS.md: integers for geometry), so they land on 9 and 16.
  Closing it needs half-point coordinates in the frame format. This is all of the header's
  difference (more for the long hands-free and failed labels).
- **Shadows** differ by up to 5 levels (7 at corners): SwiftUI's blur is not exactly a Gaussian,
  and Cairn's is one fitted to it (σ = 1.05 × radius; `shadowsAreSwiftUIs`).
- **The clock's x** is up to a quarter pixel off: it is right-aligned at a fractional point in
  the original and at a whole point here.
- **Mid-ease positions** are whole points, so they step by up to 1.7 px from the original's.
- **Not compared on screen:** Cairn's own display latency. The motion frames are rendered at the
  original's frame times less its 20 ms from change to screen; Cairn's on-screen latency is
  assumed the same, not measured.
- **Levels** come from Cairn's microphone, which taps 20 ms buffers, so the tape's history gets a
  level every 20 ms; the original's taps 2048 frames (43 ms at 48 kHz). Driving the tape from the
  same levels gives the same pixels (above), but live, Cairn's scope follows the voice more
  finely. Matching it needs a per-recording tap size in `Sub.record`.
- **A transcript that becomes empty while shown** (not something Yap does: a new recording starts
  a new panel) switches at once instead of fading out the old text.
- **Colour tagging.** The original's tape layer is untagged and Cairn's is sRGB; on the Studio
  Display both read as the same sRGB values (the comparison matches both to sRGB first).

## Testing

What runs without a person, the microphone or the keyboard:

- **Proofs.** `lake build Examples` checks the claims; `make audit` and `make kernel` check
  their axioms.
- **Self test.** `cd host && swift run CairnYap --selftest` (in `make selftest`) runs the real
  host threads with the surfaces detached and fakes for the microphone, key, typing, OpenAI
  (a `URLProtocol` stub) and the files (a scratch home): launch, hold, tap and hands free,
  shortcut cancel, silent clip, failed type, Copy Last and Recent, config and dictionary live
  reload, Keep Transcripts and Press Return from the menu, Recent holding five, the original
  Yap starting and quitting, the menu's Open items, Dictate off and Quit.
- **Fuzz.** `make fuzz-yap` (and `make fuzz-quick`): a random host against the model's `step`,
  then against the app's `receive` and menu (docs/fuzz.md).
- **Conformance.** `make conformance APP=Yap`: the app under `--debug-socket` against the
  model. Under the socket the app's world is silent (no device, no reply), so this covers the
  menu and its moves from launch, not dictation (docs/trusted.md, "Conformance").

### Manual checklist (a person, with the real app)

Install, quit the original Yap, open Yap (Cairn), grant Accessibility and the microphone, and
open a text editor. Record the macOS version and the result of each line.

- [ ] **Hold.** Hold the key, say a sentence, release: the overlay shows REC with a moving
      waveform and the preview, then TRANSCRIBING, then TYPED; the text appears in the editor
      followed by a space; the overlay hides about 1.5 s later.
- [ ] **Tap.** Tap the key (under 0.3 s): REC · HANDS FREE; speak; tap again: it is typed.
- [ ] **Shortcut cancel.** Hold the key and press another key (the key + C): the recording
      stops and nothing is sent or typed.
- [ ] **Silent clip.** Hold the key for a second without speaking: nothing is sent; the
      status line says why.
- [ ] **Failed type.** Start a dictation, then quit the editor before it types (or switch to
      an app that refuses typing): Basso plays, the overlay says NOT TYPED · IN RECENT
      TRANSCRIPTS for about 4 s, and Recent Transcripts shows it with ⚠︎. Copy Last
      Transcript copies it.
- [ ] **Config live reload.** Edit Settings… opens config.json; change `"key"` (say to `"f13"`)
      and save: the menu says Dictate with F13 and the new key works, the old one doesn't.
      Change it back.
- [ ] **Dictionary.** Edit Dictionary… opens dictionary.txt; add `kubernetes => Kubernetes`
      and dictate "kubernetes": it is typed as "Kubernetes"; "kubernetesish" is not changed.
- [ ] **Recent Transcripts.** After six dictations it lists the newest five; choosing one
      copies it. Open Transcripts Folder shows today's `.jsonl` with each line, typed ones
      marked `"typed":true`.
- [ ] **Retention.** With `"retentionDays": 1`, a day file from two days ago (copy one and
      rename it) is deleted at the next launch; today's never is.
- [ ] **Press Return After Dictating.** Turn it on: the next dictation is followed by Return,
      not a space.
- [ ] **Original Yap.** Open Yap.app while Yap (Cairn) runs: within 2 s the menu says "Yap
      is running…" and the key belongs to Yap. Quit Yap.app: Yap (Cairn) takes it back.
- [ ] **Quit** from the menu (⌘Q with it open).

## GOAL.md "Done means": status

1. **The app.** Every README behaviour is implemented and checked in the self test against
   fakes; the real day of use (microphone, key, OpenAI, typing) is Nate's, with the checklist
   above.
2. **Effects in Cairn.** Done: clock, timers, requests and subscriptions in the framework,
   each kind an `assume` claim with trusted fuzz checks (docs/effects.md, docs/trusted.md,
   ^1000–^1002 added for this app).
3. **Surfaces.** Done (docs/surfaces.md); Yap's menu and overlay are built on them.
4. **Claims and proofs.** Done, now over the app machine: ^311–^323, ^346 and ^347 are invariants of
   `Examples.Yap.machine` proved through `receive` and `menuStep`; the menu moves and flows
   (^340, ^341) as in M1.
5. **Fuzzed.** Done: the model and the app against a random host, and the host's effects in
   the trusted fuzz suites.
6. **Measured.** Partly: app size and step costs in [bench/yap.md](../bench/yap.md). Key-up to
   typed against the original with the same audio, and idle CPU and memory, need the real app
   running and are not measured yet.
7. **Mapped and written down.** `docs/trusted.md` lists the new assumptions. The map doesn't
   cover Yap yet: `tools/map` doesn't know surfaces (a status item's menu, a panel), only
   windows; that is open in workstream N's `map-own` lane.

## Differences from the original

docs/yap-parity.md audits every behaviour against the original, with the bugs the port fixes
(each filed on iamnbutler/yap) and the differences still open. The model's are in
`lean/Examples/Yap/README.md`. The app adds:

- the model (`defaults read dev.yap.Yap model`) is read again as each recording starts, as
  Yap's preview reads it (Yap reads it for the clip at key-up);
- Dictate with Key and Press Return After Dictating start from the original's defaults, then
  live in Cairn's `prefs.json`;
- it stands aside for the original Yap (^346);
- a typed transcript is marked `"typed":true` in its day file only once the append that wrote
  its line is answered (^347). The host runs requests concurrently and nothing orders their
  completion (docs/effects.md), so marking as soon as the type was answered could read the file
  before the line landed and leave it `"typed":false` (the self test caught it, two runs in
  three). A mark waits until no append is in flight, and a mark's rewrite is checked once the
  appends sent meanwhile are answered, re-appending any line it lost. If the append failed,
  there is no line and no mark. If the line still isn't there after its append worked (the file
  was edited), or the mark's read or write fails, the menu says "Couldn't mark a transcript
  typed in …" instead of dropping it silently; the transcript stays `"typed":false` on disk
  and in Recent after a relaunch.
