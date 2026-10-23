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

end Cairn.Fuzz.Trusted.Claims
