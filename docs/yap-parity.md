# Yap parity audit

Yap (Cairn) against the original Yap at `~/code/yap` (commit `96ab494`), one behaviour per row. The
original is the spec. The port may differ only where it fixes a bug in the original, and each of
those has an issue on iamnbutler/yap. Line numbers are the original's.

Status:

- **same**: the port already did what the original does.
- **fixed**: it didn't, and this PR makes it match. Each fix has a test: a `#guard` in
  `lean/Examples/Yap/Tests.lean` or `AppTests.lean`, a yapfuzz check, a trusted-fuzz check or
  the CairnYap self test.
- **bug fix**: the port deliberately differs because the original is wrong. The issue is linked.
- **open**: a difference this PR doesn't settle. It needs a decision ([Open](#open)).
- **Y**: the overlay's pixels. They belong to workstream Y (lane `yap-overlay`) and aren't audited
  here.

Counts are at the [end](#counts).

## How the text rows were checked

Wherever the original leans on Swift or Foundation for text, the port was compared with that
library directly, not with its documentation:

- **Characters.** `Graphemes.lean` is Swift's own grapheme-break state machine (Swift
  `StringGraphemeBreaking.swift`, release/6.3: a fresh state per cluster, the six InCB linkers,
  backward lookback for `suffix`). The per-code-point class table was read off Swift itself by
  `tools/yap-tables/graphemes.swift`: Swift keeps its Unicode properties private, and ICU's
  table disagrees with Swift on PUA, Kirat Rai and the linkers. Compared with Swift's `count`,
  `prefix(n)` and `suffix(n)` on 120,766 generated strings: 0 mismatches.
- **Fixes.** `Fold.lean` holds the ICU tables behind `NSRegularExpression`'s
  `(?<![\w-])…(?![\w-])` with `.caseInsensitive`: where `[\w-]` matches, and each code point's
  full case folding (`u_strFoldCase`). Both come from the engine itself
  (`tools/yap-tables/fold.swift`), compared as scalars, because Swift's `==` would treat ΐ and its
  decomposition as equal. Matches are on grapheme boundaries, as `range(of:)` and ICU's matcher
  are. Compared with a copy of Yap's `DictationDictionary` on 50,000 generated
  (heard, written, text) triples: 0 mismatches.
- **Numbers.** `String(format: "%.1f")` for "Transcribing N.Ns…" goes through the nearest
  double: a tie follows where the double lies, and an exact tie rounds to even. Compared on
  24,170 frame counts and every tie: 0 mismatches.
- **JSON and dates.** `JSONDecoder` and `ISO8601FormatStyle` (6.2), checked on 6,000 generated
  dates and the edge cases in `AppTests.lean`.

The probe programs are in `tools/yap-tables/`. Run each with `swiftc -O x.swift && ./x`; it
prints the table that goes into the Lean file.

## Hotkey (`Packages/Core/Sources/Core/Hotkey.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Default key | Right Command, code 54, command flag (L21) | `Hotkey.rightCommand` | same |
| Modifier names | nine modifiers and fn (L30–41) | the same table | same |
| Aliases | `rcmd`, `ralt`, `globe`, … (L47–59) | the same | same |
| F1–F20 | codes at L64–67 | the same | same |
| `keycode:N` | a modifier's code is that modifier, else "Key N" (L84–87) | the same | same |
| Numbers | `Int("+13")` and `UInt16("+105")` accept a `+` and leading zeros | `parseNat?` does too | same |
| Normalizing | `lowercased()`, then drop space, `-` and `_` (L93–95) | was ASCII-only; now also U+212A KELVIN SIGN → `k`, the one non-ASCII letter whose full lowercase is ASCII (İ lowercases to two scalars and never matches) | fixed |

## Push to talk (`App/PushToTalk.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Monitors | global and local `flagsChanged`, `keyDown`, `keyUp` (L46–51) | `KeySource.live`, the same masks | same |
| Modifier press and release | flag bit set or clear (L57–60) | `HotkeyFilter`, the same | same |
| Ordinary key | first keyDown (repeats ignored), keyUp (L61–66) | the same | same |
| Chord | any other keyDown while held (L67–68) | `otherKey` while held | same |
| Key changed mid-hold | the old key is released (L16–24) | the machine releases it (README, "Latch timer") | same |
| Accessibility prompt | `ensureAccessibilityPermission()` prompts once at launch (L33–40, Yap.swift L162) | `permission accessibility true` at boot | fixed (earlier commit in this PR) |

## Dictation (`App/Yap.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Ready line | "Hold K to dictate, or tap to start and tap to send" (L33) | `ready` | same |
| Tap limit, minimum, latch limit, silence peak | 300 ms, 0.3 s, 600 s, 500 (L77–87) | the same constants | same |
| Peak of `Int16.min` | counted as `Int16.max` (L511) | the same | same |
| Begin | target = frontmost app, recorder reset, "Listening…" (L231–263) | the same, `startRecording` asks for the front app | same |
| Microphone fails to start | "Microphone failed: <error.localizedDescription>" (L259–262) | was "the microphone did not start: …"; now the error's own description | fixed |
| Microphone not yet asked | starting the engine shows the system prompt | the host returned `denied` without starting; now it starts the engine, which prompts | fixed |
| Microphone refused | the engine records silence and says "Heard nothing" (L310–313) | "Microphone failed: Microphone access is not granted" and a "Microphone Is Off: Grant It…" item | bug fix, [yap#11](https://github.com/iamnbutler/yap/issues/11) |
| Shortcut while holding | stops capture, `finish(ready)`, but `finish` leaves `.recording` (L267–276, L449–452), so Yap is stuck | back to idle (^311) | bug fix, [yap#8](https://github.com/iamnbutler/yap/issues/8) |
| Shortcut during a latch | ignored, recording goes on (L270) | the same | same |
| Tap latches | Tink, "Recording hands free. Tap K to send.", timer from key-up (L277–289) | the same (^312) | same |
| Latched send | Pop (L293–296) | the same | same |
| Too short, silent, no target | "Too short to send", "Heard nothing", "No app to type into" (L306–317) | the same (^323) | same |
| Transcribing line | `"Transcribing \(String(format: "%.1f", seconds))s…"` (L321) | was a truncating decimal; now `%.1f` through the nearest double, ties to even | fixed |
| Model | `defaults string model` read at send (L323–324); the preview reads it at its start (L383) | was read once at launch; now read again as each recording starts, the preview's moment | fixed; the final clip's read is at key-down, not key-up ([Open](#open)) |
| Dictionary | `DictationDictionary.load()` at send (L326) and preview start (L385) | watched: reported on change, a clip uses what was in force when it was sent | open |
| API key | `Secrets.openAIAPIKey()` per clip (L333–334) | the host resolves it per request | same |
| Missing key | "No OPENAI_API_KEY in the environment or <file.path>" (Secrets.swift L26) | was "no OPENAI_API_KEY in the environment or ~/…"; now Yap's text with the full path | fixed |
| Trim | `trimmingCharacters(in: .whitespacesAndNewlines)` (L338–339), scalar-based | was a narrower whitespace set; now Foundation's set, U+200B included | fixed |
| Round trip | measured from just before the upload to the reply (L335–340) | from the send to the reply ([Open](#open)) | open |
| Typed line | `"Typed \(text.count) characters (\(ms)ms round trip)"` (L358) | was "Typed N characters" counting scalars; now Swift's grapheme count and the round trip | fixed |
| Trailing space | added unless Press Return is on (L353–354) | the same | same |
| Type failure | Basso, "Couldn't type it (<reason>). It's in Recent Transcripts." (L359–364) | the same; reasons in `TextInjector`'s words | fixed (earlier commit in this PR: reasons) |
| Saved before typed | README says saved first; `remember` runs after typing (L365) | saved first, then marked typed (^315, ^347) | bug fix, [yap#6](https://github.com/iamnbutler/yap/issues/6) |
| Save failure | `detail` = "Couldn't save the transcript: …" set inside `remember`, after `finish` (L152–154), so it is what the menu shows last | was overwritten by the typed line; now said last | fixed |
| Cancelled while in flight | kept, not typed (L348) | the same (^317) | same |
| Transcription error | `finish(error.localizedDescription)` unless cancelled (L366–369) | the same | same |
| Several clips in flight | the first to finish shows idle (L319, L449–452) | transcribing until the last finishes | bug fix, [yap#9](https://github.com/iamnbutler/yap/issues/9) |
| Live preview cadence | every 250 ms, chunks cut by `Chunker`, peak ≥ 500, one chunk at a time (L380–420) | the same (integer chunker: sums of squares) | same |
| Preview prompt | dictionary prompt + `Continues from: "<last 200 characters>"` (L430–436) | was the last 200 scalars; now 200 grapheme clusters (`Graphemes.takeEnd`) | fixed |
| Preview text | fixed, trimmed, joined with spaces (L414–417) | the same | same |
| Cancel (Dictate off) | turn bumped, capture stopped, idle, ready (L438–445) | the same | same |
| Accessibility polling | every 2 s until the first grant, then never (L161–172) | every 2 s and when the menu opens, always | bug fix, [yap#10](https://github.com/iamnbutler/yap/issues/10) |
| Config polling | mtime every 2 s (L209–225) | `watchFile` | same |
| Config errors | "config.json won't parse, keeping the last settings: <DecodingError text>" (L193); unknown key "config.json: no key called "x", still using K" (L198) | the same texts, `JSONDecoder`'s messages | fixed (earlier commit in this PR) |
| Defaults `enabled`/`submits` | `register` true/false, `bool(forKey:)` (L108–111) | read from `dev.yap.Yap` at first launch, then `prefs.json` | open |
| Copy | clears the pasteboard, sets the text (L121–124) | `setClipboard` | same |

## Transcripts (`Packages/Core/Sources/Core/TranscriptLog.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| File | `transcripts/YYYY-MM-DD.jsonl`, local day (L95–98) | the same | same |
| Line | `JSONEncoder`, sorted keys, no escaped slashes, ISO 8601 (L100–105) | `transcriptLine`, the same bytes | same |
| Folder | created mode 700 (L37–39) | `appendFile` created parents with the umask's mode; now 700 | fixed |
| New file | mode 600 (L50–51) | `appendFile` creates it mode 600 | same |
| Append to an existing file | `FileHandle` seek and write (L44–47) | `open(O_APPEND)` and write | same |
| Append failure text | Foundation's (`Data.write` naming the file and folder; `FileHandle.write` naming neither) | was "open: Permission denied"; now Foundation's text for the same errno (`Files.appendFailure`) | fixed |
| A day file that can't be opened | replaced by the new line alone (`Data.write(.atomic)` fallback, L48–52) | the save fails and the file is untouched | bug fix, [yap#14](https://github.com/iamnbutler/yap/issues/14) |
| Recent | newest 5, newest file first, bad lines skipped (L57–70) | the same | same |
| Recent's lines | split on `isNewline`, so U+2028, U+2029 and U+0085 inside a transcript split it (L61) | split on LF | bug fix, [yap#13](https://github.com/iamnbutler/yap/issues/13) |
| Retention | deletes every `.jsonl` whose name sorts before the cutoff (L72–93) | deletes day files older than the cutoff only | bug fix, [yap#12](https://github.com/iamnbutler/yap/issues/12) |
| Retention timing | at launch and after each saved transcript (Yap.swift L115–118, L151) | the same (^320) | same |
| A BOM | `String(contentsOf:encoding: .utf8)` drops it | dropped | fixed (earlier commit in this PR) |
| Dates | `JSONDecoder` `.iso8601` | `Dates.parseIso`, as Foundation reads them | fixed (earlier commit in this PR) |

## Config (`Packages/Core/Sources/Core/Config.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Defaults | keepTranscripts true, retentionDays 30, overlay true, key "rightCommand" (L17–26) | the same | same |
| Missing or unreadable file | defaults (L57–58) | the same | fixed (earlier commit in this PR) |
| Decoding | `decodeIfPresent` per key, `null` as absent, `JSONDecoder` syntax (L37–52) | `Json.lean`, `JSONDecoder`-exact (trailing commas, BOMs, UTF-16/32, whole numbers through the nearest double) | fixed (earlier commit in this PR) |
| Saving | pretty-printed, sorted keys, `/` escaped, folder 700, atomic (L62–69) | `configText`, `writeFile` (atomic; parents now 700) | fixed (folder mode) |
| Edit Settings… | writes the defaults if there is no file, then opens it (Yap.swift L135–140) | the same | same |

## Dictionary (`Packages/Core/Sources/Core/DictationDictionary.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Lines | `split(whereSeparator: \.isNewline)` (L43) | the same separators | same |
| Trim | `.whitespaces` (L44), U+200B included | was narrower; now Foundation's set | fixed |
| Comments | `hasPrefix("#")` on characters (L45) | was a byte check; now on grapheme clusters (`#` + a combining mark isn't a comment) | fixed |
| Arrow | `range(of: "=>")`, on grapheme boundaries (L47) | was the first byte match; now the first match on cluster boundaries | fixed |
| Prompt | "Dictated into a Claude Code terminal session. Vocabulary: …." first 25 terms (L61–65) | the same (^321) | same |
| Fixes | ICU, case-insensitive, `(?<![\w-])` / `(?![\w-])`, in order (L68–78) | was ASCII folding and an approximate `\w`; now ICU's full folding and `[\w-]` tables, matching on cluster boundaries (^319) | fixed |
| Template | two comment lines, one blank line (YapApp.swift L98–101) | was two blank lines | fixed (earlier commit in this PR) |
| Edit Dictionary… | folder 700, writes the template if missing, opens (YapApp.swift L92–105) | the same (`writeFile` parents now 700) | fixed (folder mode) |

## OpenAI (`Packages/Core/Sources/Core/OpenAITranscription.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Endpoint, method, timeout | POST `…/v1/audio/transcriptions`, 30 s (L21, L32–33) | the same | same |
| Boundary | `yap-` and a fresh UUID, uppercase (L30) | was a fixed boundary; now `boundaryFor`: `yap-` and a version-4 UUID in capitals, one per request | fixed |
| Fields | model, `response_format` json, prompt if non-empty, then `speech.wav` as `audio/wav` (L44–60) | the same bytes | same |
| WAV | 44-byte RIFF header, 16 kHz mono PCM16 (L93–111) | `effects.clip-wav` (^967) | same |
| Success | `{"text": …}` by `JSONDecoder` (L76) | the same, with `DecodingError`'s texts | fixed (earlier commit in this PR) |
| Error | "OpenAI <status>: <error.message>" else the first 500 bytes, lossy UTF-8 (L69–75, L85) | the same | fixed (earlier commit in this PR) |

## Secrets (`Packages/Core/Sources/Core/Secrets.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Order | environment, then `secrets.env` (L14–19) | the same | same |
| `.env` parsing | `KEY=value`, `#`, `export `, quotes (L30–53) | `SecretSource.parseDotEnv`, the same | same |
| Missing key | see Dictation | | fixed |

## Typing (`App/TextInjector.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Checks | empty, Accessibility, running (L38–44) | the same, with the same texts | fixed (earlier commit in this PR: texts) |
| Activation | activate, poll 25 ms up to 0.6 s (L61–74) | `Typist`, the same | same |
| Runs | per character (grapheme), at most 20 UTF-16 units unless one character is longer (L78–91) | the same | same |
| Events | key code 0 with the Unicode string, HID source, HID tap, 4 ms apart; Return is 36 (L98–114) | the same | same |

## Microphone (`App/AudioCapture.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Engine | `AVAudioEngine`, no voice processing, converted to 16 kHz mono PCM16 (L9–80) | `Microphone.live`, the same | same |
| Tap size | 2048 frames (L33) | 20 ms windows to Lean | open |

## Menu (`App/YapApp.swift`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Icon | `waveform`, `mic.fill`, `text.bubble` (L23–29) | the same symbols | same |
| Status line | `detail` (L36) | the same | same |
| Accessibility item | "Accessibility Is Off: Grant It…", opens Privacy_Accessibility (L37–42) | the same | same |
| Copy Last Transcript | disabled when there are none (L45–48) | the same | same |
| Recent Transcripts | "None yet", up to 5, then Open Transcripts Folder (L49–58) | the same | same |
| Recent label | time, ⚠︎ if not typed, the text's lines joined by spaces, 60 characters then "…" (L83–88) | was 60 scalars; now 60 grapheme clusters | fixed |
| Open Transcripts Folder | creates the folder (700), then opens it (Yap.swift L126–131) | opened without creating it, so it failed before the first transcript; now `makeDir` (new, ^1003), then open | fixed |
| Toggles | "Dictate with K"; "Press Return After Dictating" (disabled when off); "Keep Transcripts (N Days)" (L61–70) | the same | same |
| Edit items | "Edit Dictionary…", "Edit Settings…" (L73–74) | the same | same |
| Quit | "Quit Yap", ⌘Q (L77–78) | "Quit Yap (Cairn)", ⌘Q | open |
| Failed menu actions | nothing happens and nothing is said (Yap.swift L126–140, YapApp.swift L92–105) | the failure is shown in the menu | bug fix, [yap#15](https://github.com/iamnbutler/yap/issues/15) |
| Original running | (n/a) | "Yap is running. Quit it to dictate with K here." (^346) | open |

## Bundle (`App/Info.plist`, `project.yml`, `App/Yap.entitlements`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Microphone text | "Yap listens while you hold or tap Right Command." | was "Yap (Cairn) listens while you hold or tap the dictation key."; now Yap's | fixed |
| Minimum macOS | 26.0 | was 14.0; now 26.0 | fixed |
| `CFBundleDevelopmentRegion`, `CFBundleInfoDictionaryVersion` | `en` (Xcode's default), 6.0 | were missing; now set | fixed |
| Name and identifier | Yap, `dev.yap.Yap` | Yap (Cairn), `dev.yap.cairn` | open |
| `LSUIElement` | true | true | same |
| Entitlements | no sandbox, audio input, hardened runtime | the same | same |
| Signing | Apple Development, team 8S43JJMN6B | the first valid Apple Development identity | same |

## Overlay (`App/Overlay.swift`, `App/Overlay.metal`)

| Behaviour | Original | Port | Status |
|---|---|---|---|
| Pixels | Overlay.swift, Overlay.metal | View.lean's overlay | Y |
| Hide after typed and after failure | 1.5 s and 4 s (Yap.swift L357, L362) | the same | same |
| A microphone failure | hides the panel without showing it | shows it, then hides it | Y |

## Open

These need Nate. None of them is a bug in the original, so by this audit's rule each should
match the original, but matching it costs something the brief didn't settle.

1. **Name, identifier, Quit title, `prefs.json`, ^346.** "Yap (Cairn)" and `dev.yap.cairn` keep
   the port beside the original instead of replacing it: separate TCC grants, its own defaults
   (`prefs.json`), the "Yap is running" line and Quit Yap (Cairn). Matching means one app
   replacing the other.
2. **The model read.** Yap reads `model` at key-up for the clip. The port reads it at key-down,
   which is what Yap's preview does. Reading at key-up would put a host round trip before the
   upload.
3. **The dictionary read.** Yap reads `dictionary.txt` at each send. The port uses the
   last version the file watch reported, so an edit saved during a recording may miss that clip.
4. **The round trip.** Yap's timer starts after reading the key; the port's starts at the send.
   The difference is the key's file read, under a millisecond.
5. **Defaults' numbers.** `UserDefaults.bool` is true for the number 2. `readDefault` (^1002)
   returns numbers and strings both as text, so the port can't tell the number 2 from the string
   "2", which `bool` reads as false.
6. **Tap size.** Yap's level comes from 2048-frame buffers (about 43 ms at 48 kHz); the port's
   from 20 ms windows. This changes the waveform's cadence (Y).
7. **Recent labels across a DST change.** The port formats times with the zone offset at
   launch.

## Counts

| Status | Rows |
|---|---|
| same | 57 |
| fixed (this PR) | 36 |
| bug fix (intentional; yap#6 and #8–#15) | 9 |
| open (needs Nate) | 7 |
| Y (overlay pixels) | 2 |
