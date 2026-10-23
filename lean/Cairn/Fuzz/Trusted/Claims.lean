module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab

/-! The trusted base's assumptions (docs/trusted.md), each naming the check of the trusted-base
fuzzer that gathers its evidence (`make fuzz-trusted`, `build/fuzz/trusted.json`, docs/fuzz.md
"Trusted base"). Evidence, not proof: these stay assumptions.

Ids 901–999 are for framework-level assumptions; apps' own assumptions use their apps' ranges.
Not imported by `Cairn` (the host links that); the ledger reads this module as a root. -/

namespace Cairn.Fuzz.Trusted.Claims

assume ^901 swiftFrameDecoder "The Swift frame decoder agrees with Lean's" where
  does "For every byte buffer, the host's Frame(bytes:) accepts exactly when Lean's proved decodeFrame does, and then decodes the same frame."
  check "frame.decode"

assume ^902 swiftEventEncoder "Lean decodes what the Swift event encoder writes" where
  does "For every batch of events, Lean's proved decodeEvents decodes the host's encodeEvents bytes to the same events, and Lean's encoder gives back the same bytes."
  check "events.encode"

assume ^903 textIndex "UTF-16 offsets and scalar indices convert exactly" where
  does "TextIndex maps between AppKit's UTF-16 offsets and Lean's scalar indices exactly on boundaries, rounds offsets inside a surrogate pair to a whole scalar, and clamps AppKit ranges (NSNotFound, negative, past the end) to whole scalars."
  check "text.index"

assume ^904 textShadow "The text-input shadow predicts Lean's field" where
  does "Between an input-method call and the frame that reflects it, the host's copy of the focused field has the text, selection and marked range Lean's field will show."
  check "text.shadow"

assume ^905 inputClientGeometry "Input-method geometry agrees with Lean's caret" where
  does "selectedRange and markedRange are Lean's, firstRect at the selection is Lean's caret, and characterIndex(for:) maps points back to scalar boundaries of the field."
  check "text.input-client"

assume ^906 textMetricsHost "The host's text metrics are what layout assumes" where
  does "cairn_text_metrics gives one offset per scalar boundary, from 0 and nondecreasing, with nonnegative ascent and descent, and Lean's TextMetrics.host sees those numbers unchanged."
  check "text.metrics"

assume ^907 textCaretsPainted "Carets follow the painted glyphs" where
  does "On left-to-right text, the caret offset after each grapheme is at or right of every glyph painted for the text before it."
  check "text.metrics.carets"

assume ^908 hostClock "The host's clock is monotonic milliseconds" where
  does "Every batch the host sends Lean starts with exactly one clock event; its monotonic milliseconds never decrease from batch to batch and are not ahead of the system's monotonic clock, its wall time is the wall clock and its zone the current UTC offset."
  check "clock.monotonic"

assume ^909 hostWake "The host wakes Lean by wake" where
  does "When a frame carries a wake deadline, the host sends a clock-only batch whose time is at or past the deadline, soon after it, and sends none for a deadline that a later frame cleared or met."
  check "clock.wake"

assume ^910 hostReadFile "readFile replies with the file's bytes, or failed" where
  does "readFile answers with exactly the bytes the file holds, notFound for a missing file, a failure for a directory or an unreadable file, and invalid for a path that can't name a file."
  check "effects.read-file"

assume ^911 hostWriteFile "writeFile is atomic, and replies done only when the bytes are there" where
  does "writeFile answers done only when the file then holds exactly the bytes, creating missing directories; a reader alongside sees the old bytes or the new ones, never a mix; a failed write leaves the old file unchanged; a path that can't name a file is invalid."
  check "effects.write-file"

assume ^912 hostPlaySound "playSound starts a known sound and refuses an unknown one" where
  does "playSound finds every system sound by its name and answers done once it starts; any other name is answered notFound, once, without playing anything."
  check "effects.sound"

assume ^913 hostHttp "http sends the request as given and returns the response as received" where
  does "http sends the method, URL, headers and body as given and answers with the response's status, headers sorted by name and body exactly; a connection failure is network, no answer in time is timeout, and a non-http URL, a bad method or a header that could inject another is invalid and sends nothing."
  check "effects.http"

assume ^914 hostReplyOnce "The host answers every request exactly once, with its id" where
  does "Every request the host runs is answered at most once and, when its handler answers, exactly once, under its own id with the handler's first answer; a kind with no handler is answered invalid; after the app starts over no answer to an earlier request is sent."
  check "effects.reply-once"

assume ^915 hostEvery "every ms ticks while started and never after it is stopped" where
  does "An every subscription ticks under its id only while it is started and not yet stopped, at most once per period, and the host's running subscriptions are exactly those the frames started and did not stop."
  check "subs.every"

/-! Yap's host effects (workstream T, docs/effects.md "What Yap needs"), ids 960–989. -/

assume ^960 hostAppendFile "appendFile adds exactly the bytes at the end, or fails and adds nothing" where
  does "appendFile answers done only when the file then holds its old bytes followed by exactly the new ones, creating the file with mode 600 and missing directories; appends from several threads each land whole; a directory, a path under a file, a read-only file and a path that can't name a file fail and leave the file unchanged."
  check "effects.append-file"

assume ^961 hostListDir "listDir lists exactly the directory's names, sorted" where
  does "listDir answers with exactly the names in the directory, without . and .., sorted by their UTF-8 bytes; a missing directory is notFound, a file invalid, an unreadable directory denied."
  check "effects.list-dir"

assume ^962 hostDeleteFile "deleteFile removes a file or a link, never a directory" where
  does "deleteFile answers done only when the file or link (not its target) is gone, notFound when there is none, invalid for a directory, which stays, and denied when its directory is read-only, leaving the file."
  check "effects.delete-file"

assume ^963 hostWatchFile "watchFile reports every change to its file, and nothing after its stop" where
  does "While a watchFile subscription runs, every write, replacement, append, creation, removal, touch or mode change of its file is followed by a changed event within a few polls, an untouched file brings none, and after its stop has been handled none is sent."
  check "subs.watch-file"

assume ^964 hostFrontmostApp "frontmostApp answers the app in front" where
  does "frontmostApp answers with the process id and name of the app the system reports in front, notFound when there is none; the pid names a running process."
  check "effects.frontmost-app"

assume ^965 hostPermission "permission answers whether the app holds it, and prompts only when asked" where
  does "permission answers flag true exactly when the app holds Accessibility (AXIsProcessTrusted) or the microphone (authorized); the system is asked to prompt only when prompt is set, the microphone only while undecided, answering with the person's choice; each request is answered once."
  check "effects.permission"

assume ^966 hostRecord "record streams the levels of exactly the samples it keeps, and nothing after its stop" where
  does "While a record subscription runs, its audio events count every sample the clip keeps, in order, and their windows are the 20 ms levels (sum of squares and peak of each 320 samples) of those samples from the start of the clip, however the microphone split them; after its stop has been handled none is sent and the clip is finished; a microphone that can't start (no permission, no device) is one failed event and an empty clip, and the microphone is never started without the permission."
  check "subs.record"

assume ^967 hostClipWav "A clip's WAV for a range of windows holds exactly those samples" where
  does "An upload's wav part for clip c and windows s to e is a 16 kHz mono 16-bit RIFF/WAVE file of exactly samples 320 s to 320 e of the clip (to the end of the clip when e is none, waiting for a clip whose recording is being stopped); a range past the end or backwards is invalid, an unknown or forgotten clip notFound, and forgetClip answers done once and notFound after."
  check "effects.clip-wav"

assume ^968 hostGlobalKey "globalKey reports the hotkey's press and release, and other keys while it is held" where
  does "A globalKey subscription reports keyDown and keyUp of the hotkey and otherKey for any other key pressed while it is down, as Yap's PushToTalk does (a modifier by its flag in flagsChanged, an ordinary key by key down without repeats and key up, no repeated state), with monotonic times; without Accessibility it reports failed denied and installs nothing; after its stop has been handled none is sent."
  check "subs.global-key"

assume ^969 hostTypeText "typeText types exactly the text into that app, or nothing" where
  does "typeText posts the text as key events whose payloads, in order, are exactly its UTF-16 units, at most 20 per event and never splitting a character, then Return only when asked, and only after the app with that pid is in front; empty text is invalid, no Accessibility denied, no such app notFound and an app that won't come forward failed, and then nothing is posted."
  check "effects.type-text"

assume ^970 hostUpload "upload sends the body assembled from its parts, with the secret in its header" where
  does "upload sends one request whose body is its parts in order, each wav part replaced by the clip's WAV, with its headers and, for a secret, the header scheme ++ value; a missing clip, bad range or missing secret fails before anything is sent; otherwise it answers as http does."
  check "effects.upload"

assume ^971 hostSecret "A secret is read from the environment or its file, and never shown" where
  does "A secret's value is the environment variable if set and not empty, else its line in the KEY=value file as Yap's Secrets.parseDotEnv reads it (comments, export, quotes, a later line wins); a missing one is failed notFound; the value appears in the request's header and in no reply, failure message or debug description."
  check "effects.secret"

/-! Wrapped text (workstream V, docs/layout.md "Wrapped text"), ids 990–999. -/

assume ^990 wrapPainted "Wrapped lines paint as wide as Lean measured them" where
  does "On left-to-right text without controls or tabs, each line Lean's wrapping chose, shaped again on its own by the host, is within 1 + ceil(0.15 em) points of the width Lean took from the whole string's carets, and so fits the width up to that slack; laid lines sit at x 0, one line height apart."
  check "text.wrap.painted"

assume ^991 wrapCoreText "Lean breaks lines where Core Text would" where
  does "On left-to-right letters, digits and spaces, Lean's lines are Core Text's (CTTypesetterSuggestLineBreak, trailing spaces trimmed) except where a line is within one point of the width or a word is cut, where the cut is within two scalars of Core Text's."
  check "text.wrap.coretext"

/-! Surfaces (workstream S, docs/surfaces.md): menus and overlay panels, ids 940–959. -/

assume ^940 hostMenuRender "The native menu shows exactly the frame's menu records" where
  does "After each frame, a status item's NSMenu tree holds the frame's menu records in order: each item's title, enabled state, checkmark, key equivalent and ref, separators where they are, each submenu under its item with its own records, and status lines shown but not actionable; updating it in place or rebuilding it gives the same tree."
  check "menu.render"

assume ^941 hostMenuSelect "Choosing a menu item reports that item's ref" where
  does "When AppKit performs a menu item's action, the host sends exactly one menuSelect with the status item's place and that item's ref, and nothing for a status line, separator or submenu; Lean checks the ref against the menu it is showing (menu_select_stale)."
  check "menu.select"

assume ^942 hostMenuOpenClose "Opening and closing the menu are reported once each" where
  does "When the status item's menu opens the host sends one menuOpen with its place, and one menuClose when it closes; submenus opening and closing send nothing."
  check "menu.open-close"

assume ^943 hostPanelInert "An overlay panel never takes focus or clicks" where
  does "Every overlay panel is a non-activating panel that cannot become key or main, ignores the mouse, sits at status-bar level on every Space and over full-screen apps, is not hidden when the app deactivates and is transparent, whatever frames it is given."
  check "panel.inert"

assume ^944 hostPanelPlace "An overlay panel is where its anchor says" where
  does "A shown panel's frame has its canvas's size, horizontally centred in the chosen screen's visible frame and the anchor's offset above its bottom, on whole points; the screen is chosen when it appears and kept until it is hidden."
  check "panel.place"

end Cairn.Fuzz.Trusted.Claims
