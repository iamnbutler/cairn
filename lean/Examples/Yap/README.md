# Yap: the dictation machine

Yap's dictation behaviour (`~/code/yap`, `App/Yap.swift`, `App/PushToTalk.swift` and
`Packages/Core`) as one total, pure Lean function, with its claims proved and fuzzed (M2 step
1a), and the Cairn app built on it (step 3, docs/yap.md): `Examples.Yap.machine` over
`AppState`, whose `receive` turns host messages into the machine's inputs and its commands into
framework effects, with a status-item menu and an overlay panel.

```
step : State → Input → State × List Cmd        -- Examples/Yap/Model.lean
```

| File | What |
|---|---|
| `Model.lean` | `State`, `Input` (everything the host reports), `Cmd` (everything Lean asks of it), `step` |
| `Dictionary.lean` | `dictionary.txt`: parsing, the prompt (first 25 terms), whole-word case-insensitive fixes, with `replaceWord_replaces` |
| `Chunker.lean` | the live preview's cut at a pause, in integers (sum of squares per 320-sample window) |
| `Hotkey.lean` | key names in `config.json` (modifiers, aliases, `f1`–`f20`, `keycode:N`) |
| `Retention.lean` | the recent five; which day files to delete, with `today_not_deleted` |
| `Proofs.lean`, `Sending.lean`, `Recording.lean`, `Once.lean`, `Recent.lean` | the theorems the claims cite |
| `../Yap.lean` | the claims, ^301–^341 |
| `Tests.lean` | `#guard` scenarios replaying the README's behaviours |
| `App.lean` | the app: `AppState`, `receive` (messages → inputs), `tr` (commands → effects), files, the upload, `subscriptions` |
| `View.lean` | the status item's menu (^301) and the overlay panel (^345) |
| `AppProofs.lean` | the claims through `receive` and `menuStep` (`app_*`, `Keeps`, `TypedInv`) |
| `AppTests.lean`, `OnScreen.lean` | `#guard`s through `receive`; each invariant on screen in reachable states |
| `Abi.lean` | the C ABI the CairnYap host links (`libcairn_app_yap`) |
| `Fuzz.lean`, `AppFuzz.lean`, `../../YapFuzz.lean` | `lake exe yapfuzz` / `make fuzz-yap`: a random host against `step`, then against the app |

## Claims

The claims are stated over the app machine (`Examples/Yap.lean`): the menu items are `move`s
(^302–^310, ^342–^344) whose effects are the app's, and everything about dictation is an
`invariant` over `AppState` whose `holds` quantifies over every message the host can send
(`receive`) and every menu item (`menuStep`), so `steps_reachableAll` covers runtime steps. Each
cites an `app_*` theorem in `AppProofs.lean`, proved from the model theorem below. ^346 (the
original Yap keeps its key) and ^347 (a mark waits for the appends) are new with the app.

| Id | Claim | Proved (model) | Fuzzed | Tested |
|---|---|---|---|---|
| ^311 | a shortcut never sends (only the clock can, for a latch's 10-min limit) | `shortcut_never_sends` | yes | yes |
| ^312 | hold/tap split is exactly 300 ms | `hold_tap_split` | yes | 299 vs 300 ms |
| ^313 | one recording at a time: start only when none, stop before it leaves | `step_start`, `step_ends` | yes | yes |
| ^314 | every recording ends 10 min after the key is up | `step_recInv`, `recording_ends` | yes | yes |
| ^315 | a transcript is kept, and its save issued, before the type command | `saved_before_typed` | yes | yes |
| ^316 | a failed type is first in Recent, flagged, with the error sound | `failed_type_flagged` | yes | yes |
| ^317 | only an uncancelled transcription still in flight types | `late_reply_never_types` | yes | yes |
| ^318 | each clip is typed at most once, along every input sequence | `typed_once`, `typed_once_from` | over the run | duplicate reply |
| ^319 | the typed text is the transcript with fixes on whole words, trimmed | `typed_text`, `replaceWord_replaces` | text formula | yes |
| ^320 | retention never deletes today | `retention_never_today` | yes | yes |
| ^321 | only the first 25 terms reach the model | `step_prompt` | yes | yes |
| ^322 | Recent holds at most five | `step_small` | yes | 7 clips |
| ^323 | too short, silent or no app: never sent | `step_transcribe` | yes | yes |
| ^330–^337 | assumptions about the host (keys, ticks, request ids, audio, typing, files, days) | stated | | |
| ^340, ^341 | flows through the menu | `decide` | | |
| ^347 | a mark (`"typed":true` on disk) waits for the appends | `receive_marks` and friends (`MarkProofs.lean`, of the app, not the model) | yes, with a host that keeps the day files and answers in any order | yes |

All of it is closed without `sorry` or compiler-trusting tactics, on the standard three axioms (`make audit`).

**Fuzzing.** `lake exe yapfuzz` plays a random host in two modes; the second (`AppFuzz.lean`)
sends the app's `receive` messages and menu items, answers the requests it makes, and checks
^311–^323, ^346 and ^347 as the app states them (docs/fuzz.md). The first plays it against `step`: key presses with random timings (taps,
holds, repeats, a release that never comes), shortcuts, ticks early, late and jumping (ten
minutes forward, seconds back), audio loud, quiet and for the wrong clip, microphone failures,
replies slow, failed, duplicated, out of order, to nothing or never, config and dictionary
edits (bad keys, unreadable files, 40 terms), day files and the menu. Every step is checked
against each claim; failures are shrunk with ddmin and printed as a Lean list. It imports the
model only, so it builds against a mutated model: dropping the cancel check (^317), not
consuming a reply (^318), `≤` for `<` at 300 ms (^312), a 100-frame minimum (^323) and starting
a second recording (^313) are each caught in 300 sequences and shrunk to 2–15 inputs.

## What the host must do (^330–^337)

Report the dictation key down and up once each with a monotonic millisecond clock, and every
other key pressed while it is down; deliver a `tick` at or after each `wakeAt`; run a step's
commands in order and answer requests by id (replies may be late, fail, repeat or never come);
report audio per clip as frames, peak and complete 320-sample windows; transcribe what it is
asked; type into the given process and say whether it worked; report `config.json` and
`dictionary.txt` on change; list day files by day number. Swift decides nothing else.

## Differences from Swift Yap, and why

The original is the spec; docs/yap-parity.md audits every behaviour against it. The model
differs only where Swift Yap has a bug, each filed on iamnbutler/yap:

- **Saved before typed** ([yap#6](https://github.com/iamnbutler/yap/issues/6)). Yap's README
  says "every transcript is saved before Yap tries to type it", but `send()` calls `remember`
  *after* `TextInjector.type` returns. The model keeps and saves first, then types, then issues
  `markTyped` when typing succeeds (^315). A failed type therefore moves the transcript to the
  front again (`flagFailed`), which gives the order Swift's late `remember` gives.
- **A shortcut ends the recording** ([yap#8](https://github.com/iamnbutler/yap/issues/8)).
  Swift stops the capture but `finish` leaves the state `.recording`, so Yap is stuck until a
  long press. The model goes back to idle (^311).
- **Several clips in flight** ([yap#9](https://github.com/iamnbutler/yap/issues/9)). Swift shows
  idle as soon as the first finishes; the model's phase is derived from the requests still in
  flight. Overlapping clips type in reply order.
- **A refused microphone** ([yap#11](https://github.com/iamnbutler/yap/issues/11)) is
  "Microphone failed: …", not a silent recording and "Heard nothing".

Not differences, only stated:

- **A held recording has no limit.** Only a latched recording times out at ten minutes, as in
  Swift. So "every recording ends" holds once the key is up (^314).
- **"Heard nothing" after a cancel.** Swift sets the status line from an empty transcript even
  after a cancel, and so does the model; a failed transcription after a cancel leaves the
  status line alone, as Swift does.
- **Text is Swift's.** Character counts, the 60-character preview and the 200-character context
  are grapheme clusters (`Graphemes.lean`, Swift's own break rules); fixes match as ICU's
  case-insensitive `(?<![\w-])…(?![\w-])` does (`Fold.lean`); "Transcribing N.Ns…" is `%.1f`;
  "Typed N characters (Nms round trip)". The tables come from Swift and ICU themselves
  (`tools/yap-tables/`).
- **The chunker is integers.** Swift's RMS in `Double` becomes a comparison of sums of squares;
  the constants (23 pause windows, cuts between 60 and 500 windows, an 11-window tail) are
  Swift's.
- **Latch timer.** Swift's starts at the tap's key-up; so does the model's deadline. A shortcut
  during a latch is ignored and the recording goes on, as in Swift; a key change in
  `config.json` mid-hold releases the old key.
- **Open** (docs/yap-parity.md, "Open"): the dictionary is reported on change rather than read
  per clip, and the model is read at key-down rather than key-up.

## On the framework

`Cmd` stays local to the model: `App.lean`'s `tr` sends each request as a framework request
under id `2q` (the app's own requests use odd ids), `wakeAt` becomes a timer, and the rest are
the app's own requests or one-way effects. See docs/yap.md for the app.
