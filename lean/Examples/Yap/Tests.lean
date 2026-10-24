import Examples.Yap.Model

/-! Scenario tests for the dictation machine: each replays a behaviour from Yap's README
(`~/code/yap/README.md`) or a rule from `App/Yap.swift` through `step`, and checks the commands
and state that come out. -/

namespace Examples.Yap.Tests
open Examples.Yap

def front : Target := ⟨42, some "Terminal"⟩

/-- `n` samples of speech, as 20 ms windows. -/
def loud (windows : Nat) : Audio :=
  { frames := windows * 320, peak := 4000, windows := List.replicate windows ⟨320 * 2000 * 2000, 4000⟩ }
def hush (windows : Nat) : Audio :=
  { frames := windows * 320, peak := 20, windows := List.replicate windows ⟨320 * 10 * 10, 20⟩ }

def boot : List Input := [.launch {}, .config .missing, .dictionary "", .trust true]
def cmds (is : List Input) : List Cmd := (exec init is).2
def st (is : List Input) : State := run init is
def has (is : List Input) (c : Cmd) : Bool := (cmds is).contains c
def sends (cs : List Cmd) : Bool := cs.any fun | .transcribe .. => true | _ => false
def types (cs : List Cmd) : List (Nat × String × Bool) :=
  cs.filterMap fun | .type _ c _ t r => some (c, t, r) | _ => none

-- Launch: listen for Right Command, read config and dictionary; the first config read loads
-- the recent list and prunes (keep transcripts is on by default).
#guard cmds boot == [.listen Hotkey.rightCommand, .readConfig, .readDictionary, .listDays, .loadRecent 5]
#guard (st boot).detail == "Hold Right Command to dictate, or tap to start and tap to send"

/-! ### Hold to talk; release to send -/

def hold : List Input := boot ++ [.keyDown 1000 (some front), .audio 1 (loud 100), .keyUp 3000]
#guard has hold (.startRecording 1) && has hold (.stopRecording 1)
#guard has hold (.transcribe 1 1 "gpt-transcribe" none)
#guard (st hold).recording.isNone && phase (st hold) == .transcribing
#guard (st hold).detail == "Transcribing 2.0s…"
-- The transcript is saved before it is typed, with a trailing space so the next one doesn't fuse.
def holdDone : List Input := hold ++ [.reply 1 (.ok "  hello world \n")]
#guard (cmds holdDone).drop (cmds hold).length ==
  [.save 2 { clip := some 1, text := "hello world", app := some "Terminal" }, .listDays,
   .overlay 1 (.text "hello world"), .type 3 1 42 "hello world " false]
def typed : List Input := holdDone ++ [.reply 3 (.ok "")]
#guard (st typed).recent == [{ clip := some 1, text := "hello world", app := some "Terminal", typed := true }]
#guard has typed (.markTyped 1) && phase (st typed) == .idle

/-! ### Tap (under 0.3 s) for hands free; tap again to send -/

def tap : List Input := boot ++ [.keyDown 1000 (some front), .keyUp 1299, .audio 1 (loud 100)]
#guard ((st tap).recording.map (·.latched)) == some true && has tap (.play .tink)
#guard ((st tap).recording.map (·.deadline)) == some 601299
-- Exactly 300 ms is a hold: it sends.
#guard (st (boot ++ [.keyDown 1000 (some front), .audio 1 (loud 100), .keyUp 1300])).recording.isNone
#guard sends (cmds (boot ++ [.keyDown 1000 (some front), .audio 1 (loud 100), .keyUp 1300]))
def tapTap : List Input := tap ++ [.keyDown 5000 none, .keyUp 9000]
#guard has tapTap (.play .pop) && sends (cmds tapTap) && (st tapTap).recording.isNone
-- The second press's app doesn't matter; the first one's does.
#guard (st (tapTap ++ [.reply 1 (.ok "hi")])).recent.head?.map (·.app) == some (some "Terminal")

/-! ### It sends on its own after 10 minutes -/

#guard !(sends (cmds (tap ++ [.tick 601298])))
#guard (st (tap ++ [.tick 601298])).recording.isSome
#guard sends (cmds (tap ++ [.tick 601299])) && (st (tap ++ [.tick 601299])).recording.isNone
-- A clock that jumps far ahead sends it too; one that jumps back changes nothing.
#guard sends (cmds (tap ++ [.tick 99999999]))
#guard (st (tap ++ [.tick 5])).now == 1299

/-! ### A key used in a shortcut cancels -/

def chord : List Input := boot ++ [.keyDown 1000 (some front), .audio 1 (loud 100), .otherKey, .keyUp 3000]
#guard !(sends (cmds chord)) && has chord (.stopRecording 1) && (st chord).recording.isNone
-- Mid-latch, a shortcut is just you using the keyboard: the recording carries on.
def latchChord : List Input := tap ++ [.keyDown 5000 none, .otherKey, .keyUp 5100]
#guard !(sends (cmds latchChord)) && (st latchChord).recording.isSome
#guard sends (cmds (latchChord ++ [.keyDown 6000 none, .keyUp 6100]))
-- Other keys while the dictation key is up are nobody's business.
#guard sends (cmds (tap ++ [.otherKey, .keyDown 5000 none, .keyUp 5100]))

/-! ### Clips that are too short or silent are dropped -/

def short : List Input := boot ++ [.keyDown 1000 (some front), .audio 1 { frames := 4799, peak := 9000 }, .keyUp 2000]
#guard !(sends (cmds short)) && (st short).detail == "Too short to send"
#guard sends (cmds (boot ++ [.keyDown 1000 (some front), .audio 1 { frames := 4800, peak := 9000 }, .keyUp 2000]))
def silent : List Input := boot ++ [.keyDown 1000 (some front), .audio 1 (hush 100), .keyUp 3000]
#guard !(sends (cmds silent)) && (st silent).detail == "Heard nothing"
#guard !(sends (cmds (boot ++ [.keyDown 1000 none, .audio 1 (loud 100), .keyUp 3000])))
-- Audio for another clip is not this one's.
#guard !(sends (cmds (boot ++ [.keyDown 1000 (some front), .audio 7 (loud 100), .keyUp 3000])))
-- A transcript that is empty after fixes and trimming is "Heard nothing", not typed.
#guard types (cmds (hold ++ [.reply 1 (.ok "  ")])) == [] && (st (hold ++ [.reply 1 (.ok " ")])).detail == "Heard nothing"

/-! ### The dictionary -/

def dict : String := "# A comment\nlane\nautoblog\n  \nauto blog => autoblog\nlane => Lane\n=> nothing\n"
#guard Dictionary.parse dict ==
  { terms := ["lane", "autoblog"], fixes := [⟨"auto blog", "autoblog"⟩, ⟨"lane", "Lane"⟩] }
#guard applyFixes (Dictionary.parse dict).fixes "I use Auto Blog on a lane" == "I use autoblog on a Lane"
-- Whole words only, and a hyphen counts as part of a word.
#guard applyFixes (Dictionary.parse dict).fixes "planes, lanes, lane-change, my_lane, lane." == "planes, lanes, lane-change, my_lane, Lane."
#guard applyFixes [⟨"auto blog", "autoblog"⟩] "auto blogging, AUTO BLOG!" == "auto blogging, autoblog!"
#guard applyFixes [⟨"gpu", "GPU"⟩] "gpu gpu gpu" == "GPU GPU GPU"
#guard applyFixes [⟨"café", "Café"⟩] "un café noir, cafés" == "un Café noir, cafés"
-- Fixes apply to the clip's transcript before it is typed.
def fixed : List Input := boot ++ [.dictionary dict, .keyDown 1000 (some front), .audio 1 (loud 100),
  .keyUp 3000, .reply 1 (.ok "the auto blog lane")]
#guard types (cmds fixed) == [(1, "the autoblog Lane ", false)]
-- Only the first 25 terms are sent.
def terms30 : String := "\n".intercalate ((List.range 30).map (s!"t{·}"))
#guard (Dictionary.parse terms30).promptFor none ==
  some ("Dictated into a Claude Code terminal session. Vocabulary: " ++
    ", ".intercalate ((List.range 25).map (s!"t{·}")) ++ ".")
#guard (({} : Dictionary).promptFor none) == none

/-! ### Transcripts: saved before typing; a failed type is flagged and recoverable -/

def failed : List Input := holdDone ++ [.reply 3 (.failed "Terminal would not come to the front")]
#guard has failed (.play .basso)
#guard (st failed).recent.map (·.typed) == [false] && !(has failed (.markTyped 1))
#guard (st failed).detail == "Couldn't type it (Terminal would not come to the front). It's in Recent Transcripts."
#guard (cmds (failed ++ [.menu .copyLast])).getLast? == some (.copy "hello world")
-- With Keep Transcripts off, nothing is written; the transcript is still in the recent list.
def noKeep : List Input := boot ++ [.menu .toggleKeep, .reply 1 (.ok ""), .keyDown 1000 (some front),
  .audio 1 (loud 100), .keyUp 3000, .reply 2 (.ok "hi")]
#guard (cmds noKeep).any (fun | .save .. => true | _ => false) == false
#guard types (cmds noKeep) == [(1, "hi ", false)] && (st noKeep).recent.length == 1
#guard has noKeep (.saveConfig 1 { keepTranscripts := false })

-- "Typed N characters (T ms round trip)": T from sending the clip to its transcript (Yap's
-- `finish("Typed \(text.count) characters (\(elapsed) round trip)")`).
#guard (st typed).detail == "Typed 11 characters (0ms round trip)"
#guard (st (hold ++ [.tick 3450, .reply 1 (.ok "hello world"), .tick 3900, .reply 3 (.ok "")])).detail ==
  "Typed 11 characters (450ms round trip)"
#guard (st typed).trips == [] && (st holdDone).trips == [(1, 0)]
-- A failed save is the last word on its clip, whichever reply comes first: Yap saves once
-- typing is over, so its message follows "Typed …" or "Couldn't type it …".
#guard (st (holdDone ++ [.reply 2 (.failed "The disk is full."), .reply 3 (.ok "")])).detail ==
  "Couldn't save the transcript: The disk is full."
#guard (st (holdDone ++ [.reply 2 (.failed "The disk is full.")])).detail == "Transcribing 2.0s…"
#guard (st (holdDone ++ [.reply 3 (.ok ""), .reply 2 (.failed "The disk is full.")])).detail ==
  "Couldn't save the transcript: The disk is full."
#guard (st (holdDone ++ [.reply 2 (.failed "The disk is full."), .reply 3 (.failed "no")])).detail ==
  "Couldn't save the transcript: The disk is full."
#guard (st (holdDone ++ [.reply 2 (.failed "The disk is full."), .reply 3 (.ok "")])).unsaved == []
-- The next clip's typing is its own.
#guard (st (holdDone ++ [.reply 2 (.failed "The disk is full."), .reply 3 (.ok ""),
  .keyDown 9000 (some front), .audio 2 (loud 100), .keyUp 11000, .reply 4 (.ok "again"),
  .reply 6 (.ok "")])).detail == "Typed 5 characters (0ms round trip)"

/-! ### "Transcribing 1.5s…": `String(format: "%.1f")` of a double -/

#guard seconds 24000 == "1.5" && seconds 4800 == "0.3" && seconds 9600000 == "600.0"
-- Ties in the tenths go the way the double lies, and to even on an exact tie.
#guard seconds 800 == "0.1" && seconds 2400 == "0.1" && seconds 4000 == "0.2"
#guard seconds 7200 == "0.5" && seconds 10400 == "0.7" && seconds 12000 == "0.8"
#guard seconds 13600 == "0.8" && seconds 28000 == "1.8" && seconds 15200 == "0.9"

/-! ### The model default, read as each recording starts -/

def modelHold (m : Option String) : List Input :=
  boot ++ [.model m, .keyDown 1000 (some front), .audio 1 (loud 100), .keyUp 3000]
#guard has (modelHold (some "whisper-1")) (.transcribe 1 1 "whisper-1" none)
#guard has (modelHold none) (.transcribe 1 1 "gpt-transcribe" none)
-- An empty default is sent as it is, as Yap's `defaults.string(forKey:) ?? defaultModel` does.
#guard has (modelHold (some "")) (.transcribe 1 1 "" none)

/-- Dictate `n` clips, each typed. -/
def many : Nat → List Input
  | 0 => boot
  | n + 1 =>
    let is := many n
    let t := 10000 * (n + 1)
    let s := st (is ++ [.keyDown t (some front), .audio (n + 1) (loud 100), .keyUp (t + 2000)])
    is ++ [.keyDown t (some front), .audio (n + 1) (loud 100), .keyUp (t + 2000), .reply (s.nextReq - 1) (.ok s!"clip {n + 1}")]
#guard (st (many 7)).recent.map (·.text) == ["clip 7", "clip 6", "clip 5", "clip 4", "clip 3"]
#guard (types (cmds (many 7))).length == 7

/-! ### A late or duplicate reply never types -/

-- A second reply to the same request is ignored.
#guard types (cmds (holdDone ++ [.reply 1 (.ok "again")])) == types (cmds holdDone)
-- Turning dictation off cancels: the transcript in flight is kept, not typed.
def cancelled : List Input := hold ++ [.menu .toggleEnabled, .reply 1 (.ok "too late")]
#guard types (cmds cancelled) == [] && (st cancelled).recent.map (·.text) == ["too late"]
-- Dictating again while the last clip is transcribing doesn't lose it.
def overlap : List Input := hold ++ [.keyDown 4000 (some front), .audio 2 (loud 100), .keyUp 6000,
  .reply 2 (.ok "second"), .reply 1 (.ok "first")]
#guard types (cmds overlap) == [(2, "second ", false), (1, "first ", false)]

/-! ### Settings -/

-- Return after dictating: no trailing space, and Return.
def submit : List Input := boot ++ [.menu .toggleSubmits, .keyDown 1000 (some front), .audio 1 (loud 100),
  .keyUp 3000, .reply 1 (.ok "ship it")]
#guard types (cmds submit) == [(1, "ship it", true)]
-- Dictate with key off: the key does nothing; Return After Dictating can't be changed.
def off : List Input := boot ++ [.menu .toggleEnabled, .keyDown 1000 (some front), .keyUp 3000]
#guard (cmds off).all (fun | .startRecording _ => false | _ => true)
#guard (st (off ++ [.menu .toggleSubmits])).submits == false
-- config.json, live: a new key is listened for at once.
def ropt : List Input := boot ++ [.config (.ok { key := some "Right Option" })]
#guard has ropt (.listen ⟨61, some Hotkey.optionFlag, "Right Option"⟩)
#guard (st ropt).hotkey.name == "Right Option"
#guard (st (boot ++ [.config (.ok { key := some "hyper" })])).detail ==
  "config.json: no key called \"hyper\", still using Right Command"
#guard (st (boot ++ [.config (.unreadable "line 3")])).detail ==
  "config.json won't parse, keeping the last settings: line 3"
-- Changing the key mid-hold ends the hold: its release would never be heard.
def keyChange : List Input := boot ++ [.keyDown 1000 (some front), .audio 1 (loud 100), .tick 2000,
  .config (.ok { key := some "f13" })]
#guard sends (cmds keyChange) && !(st keyChange).keyHeld
#guard Hotkey.parse "RCMD" == some Hotkey.rightCommand
#guard Hotkey.parse "keycode:105" == some ⟨105, none, "Key 105"⟩
#guard Hotkey.parse "keycode:61" == some ⟨61, some Hotkey.optionFlag, "Right Option"⟩
#guard Hotkey.parse "F21" == none && Hotkey.parse "f13" == some ⟨105, none, "F13"⟩
-- The overlay off: no preview.
#guard !(has (boot ++ [.config (.ok { overlay := some false }), .keyDown 1000 (some front)]) (.overlay 1 .begin))

/-! ### Retention -/

#guard daysToDelete 30 100 [60, 70, 71, 99, 100, 101] == [60, 70]
#guard daysToDelete 1 100 [99, 100] == [99]
#guard daysToDelete 0 100 [1, 2] == []
#guard (cmds (boot ++ [.transcriptDays 100 [60, 70, 71, 100]])).getLast? == some (.deleteDays [60, 70])

/-! ### The live preview: chunks cut at pauses -/

-- 2 s of speech, then 0.5 s of quiet: one cut, in the middle of the pause: the run of 23 quiet
-- windows ends at window 122, and the cut is 11 windows after the run began (window 111).
def preview : List Input := boot ++ [.keyDown 1000 (some front), .audio 1 (loud 100), .audio 1 (hush 25), .tick 1300]
#guard Chunker.boundary ((loud 100).windows.map (·.sumSq) ++ (hush 25).windows.map (·.sumSq)) == some 111
#guard has preview (.transcribeChunk 1 1 0 (111 * 320) "gpt-transcribe" none)
-- Too early to tell: no cut.
#guard Chunker.boundary ((loud 30).windows.map (·.sumSq) ++ (hush 25).windows.map (·.sumSq)) == none
-- No pause in 10 s: cut at the quietest of the last 2 s.
#guard Chunker.boundary ((loud 450).windows.map (·.sumSq) ++ [5] ++ (loud 49).windows.map (·.sumSq)) == some 451
#guard (st (preview ++ [.reply 1 (.ok "so far")])).recording.map (·.heard) == some ["so far"]
#guard has (preview ++ [.reply 1 (.ok "so far")]) (.overlay 1 (.text "so far"))
-- The next chunk carries what came before as context.
#guard context ["so far"] == some "Continues from: \"so far\""
-- A chunk that comes back after the clip was sent is dropped; the whole clip is what's typed.
def lateChunk : List Input := preview ++ [.keyUp 3000, .reply 1 (.ok "chunk"), .reply 2 (.ok "whole")]
#guard types (cmds lateChunk) == [(1, "whole ", false)]

/-! ### The menu -/

#guard (cmds (boot ++ [.menu .copyLast])).length == (cmds boot).length
#guard (cmds (typed ++ [.menu (.copyRecent 0)])).getLast? == some (.copy "hello world")
#guard (cmds (boot ++ [.trust false, .menu .grantAccess])).getLast? == some (.open .accessibility)

end Examples.Yap.Tests
