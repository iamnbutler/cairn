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

end Cairn.Fuzz.Trusted.Claims
