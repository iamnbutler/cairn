# Yap: the dictation machine

Step 1a of M2 (GOAL.md): Yap's dictation behaviour (`~/code/yap`,
`App/Yap.swift`, `App/PushToTalk.swift` and `Packages/Core`) as one total, pure Lean function,
with its claims proved and fuzzed. There is no view and no host yet.

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
| `Fuzz.lean`, `../../YapFuzz.lean` | `lake exe yapfuzz` / `make fuzz-yap`: a random host against `step` |

## Claims

The claim commands know only machines driven by `Action`s on controls; Yap is driven by the
host. So the menu items are `move`s (^302–^310; their commands other than copying are dropped
until the framework has effects for them), and everything about dictation is an `invariant`
whose `holds` quantifies over every host input (`∀ i`) or every input sequence (`∀ is`): a
statement about `step` itself, proved for every state (or every reachable one), not just the
menu machine's.

| Id | Claim | Proved | Fuzzed | Tested |
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

All of it is closed without `sorry` or compiler-trusting tactics, on the standard three axioms (`make audit`).

**Fuzzing.** `lake exe yapfuzz` plays a random host: key presses with random timings (taps,
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

- **Saved before typed.** Yap's README says "every transcript is saved before Yap tries to type
  it", and `remember`'s doc comment agrees, but `send()` calls `remember` *after*
  `TextInjector.type` returns (Yap.swift, the end of `send`'s task). If the app quits or hangs
  while typing, the transcript is lost. The model follows the README: it keeps and saves first,
  then types, then issues `markTyped` when typing succeeds. That is ^315.
- **A held recording has no limit.** Only a latched recording times out at ten minutes, as in
  Swift. So "every recording ends" holds once the key is up (^314); a key held forever records
  forever. Not changed, only stated.
- **A failed type moves to the front.** Swift remembers the transcript once typing is over, so
  a failed one is newest; the model kept it before typing, so it moves it to the front again
  when typing fails (`flagFailed`), with the same result.
- **Several clips in flight.** Swift shows idle as soon as the first finishes; the model's phase
  is derived from the requests still in flight. Overlapping clips type in reply order.
- **"Heard nothing" after a cancel.** Swift sets the status line from an empty transcript even
  after a cancel; the model does the same (not worth a difference), but a failed transcription
  after a cancel leaves the status line alone, as Swift does.
- **Dictionary and config are watched, not read per clip.** Swift reads `dictionary.txt` per
  clip; the model asks the host to report it on change, and a clip uses the fixes in force when
  it was sent.
- **Text.** Case folding is ASCII only (Swift's `.caseInsensitive` folds more), `\w` is
  approximated (letters, digits, `_`, `-`, and non-ASCII outside a punctuation list), and the
  preview context is the last 200 scalars. "Typed N characters" omits the round-trip time (no
  wall clock in the model).
- **The chunker is integers.** Swift's RMS in `Double` becomes a comparison of sums of squares;
  the constants (23 pause windows, cuts between 60 and 500 windows, an 11-window tail) are
  Swift's.
- **Latch timer.** Swift's starts at the tap's key-up; so does the model's deadline. A shortcut
  during a latch is ignored and the recording goes on, as in Swift; a key change in
  `config.json` mid-hold releases the old key.

## For the framework (workstream Q)

`Cmd` is local. Each constructor is a request with an id answered by `Input.reply`, a timer
(`wakeAt`), or a one-way command, so it should map onto framework effects; and the claims want
machines driven by host inputs as well as `Action`s, so that `invariant` can state these over
the machine's own `update` instead of quantifying over `step`.
