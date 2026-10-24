import Cairn.Frame.Events

/-! Checks for `Cairn.Frame.Events`, kept out of the module so they can use `#guard`
(a `#guard` in a `module` needs a `meta import` of what it evaluates). -/

/-! ## Examples -/

namespace Cairn.Wire.Examples

private def axA : AxNode :=
  { control := some ⟨7, 3⟩, role := .checkbox, rect := ⟨1, 2, 3, 4⟩, label := "",
    checked := some true }
private def axB : AxNode :=
  { control := none, role := .text, rect := ⟨0, 0, 0, 0⟩, label := "x", parent := some 0 }

private def canvas : Canvas where
  size := ⟨800, -600⟩
  draws := #[.rect ⟨-5, 0, 10, 10⟩ (some ⟨1, 2, 3, 4⟩) 6 none, .pushClip ⟨0, 0, 1, 1⟩,
    .text ⟨3, 4⟩ { weight := 700, italic := true } ⟨9, 9, 9, 255⟩ "日本 🙂", .popClip,
    .rect ⟨0, 0, 1, 1⟩ none 0 (some ⟨2, ⟨0, 0, 0, 255⟩⟩)]
  ax := #[axA, axB]
  textInput := some { control := ⟨2, 0⟩, rect := ⟨1, 1, 1, 1⟩, caret := ⟨2, 2, 1, 1⟩,
                      text := "ab", selection := (1, 2), marked := some (0, 1) }
  cursor := .text

private def menu : Array MenuRecord := #[
  { kind := .info, label := "Idle", enabled := false },
  { kind := .item, label := "Enabled", control := some ⟨451, 0⟩, checked := some true },
  { kind := .submenu, label := "Recent", place := some 452 },
  { kind := .item, label := "One", control := some ⟨453, 1⟩, parent := some 2, enabled := false },
  { kind := .separator, enabled := false },
  { kind := .item, label := "Quit", control := some ⟨454, 0⟩,
    shortcut := some ⟨.char 'q', { command := true }⟩ }]

private def frame : Frame where
  surfaces := #[
    { kind := .window, place := 3, title := "Ünïcode", canvas },
    { kind := .panel, place := 455, anchor := .bottomCenter 56, screen := .main,
      canvas := { size := ⟨520, 90⟩, draws := #[.popClip], ax := #[axB] } },
    { kind := .panel, place := 456, shown := false },
    { kind := .statusItem, place := 450,
      status := { control := ⟨457, 0⟩, symbol := "waveform", title := "", label := "Tray",
                  menu } }]
  effects := #[.setClipboard "copied", .beep, .setTimer "t" 30, .cancelTimer "ü",
    .request 7 (.writeFile "~/a" ⟨#[0, 255, 1]⟩), .request 8 (.readFile ""),
    .request 9 (.playSound "Tink"),
    .request 4294967295 (.http "POST" "http://x/" [("A", "b"), ("", "")] ⟨#[1]⟩ 1000), .quit,
    .request 10 (.appendFile "~/t/2026-10-23.jsonl" ⟨#[123, 10]⟩), .request 11 (.listDir "~/t"),
    .request 12 (.deleteFile "~/t/old"), .request 13 .frontmostApp,
    .request 14 (.permission .accessibility true), .request 15 (.typeText 501 "hi 🙂" true),
    .request 16 (.upload "POST" "https://h/t" [("A", "b")] (some ⟨"Authorization", "Bearer ", "~/s.env", "K"⟩)
      [.bytes ⟨#[1, 2]⟩, .wav 3 0 none, .wav 3 2 (some 5)] 30000),
    .request 17 (.upload "GET" "" [] none [] 0), .request 18 (.forgetClip 3),
    .request 19 (.openItem "~/Library/Application Support/yap"), .request 20 (.appRunning "dev.yap.Yap"),
    .request 21 (.readDefault "dev.yap.Yap" "model"), .request 22 (.makeDir "~/a/b")]
  subs := #[.start 1 (.every 50), .stop 0, .start 2 (.watchFile "~/c.json"), .start 3 (.record 7),
    .start 4 (.globalKey 63 none), .start 5 (.globalKey 49 (some 55))]
  wake := some 18446744073709551615

#guard fitsFrame frame
#guard reprStr (decodeFrame (encodeFrame frame)) == reprStr (some frame)
-- The compiled encoder (`Put.frame`, via `@[csimp]`) writes the specification's bytes.
#guard (encodeFrame frame).data.toList == Enc.frame frame
#guard (encodeFrame frame).size == (Enc.frame frame).length
-- Trailing bytes and a wrong version are rejected.
#guard (decodeFrame ((encodeFrame frame).push 0)).isNone
#guard (decodeFrame ((encodeFrame frame).set! 4 1)).isNone
#guard (decodeFrame (encodeFrame { frame with wake := none })).isSome
#guard (decodeFrame (encodeFrame { frame with surfaces := #[] })).isSome
-- The window accessors read the first window.
#guard frame.size == ⟨800, -600⟩ && frame.ax.size == 2

private def events : Array Event := #[.pointerMove ⟨-1, 2⟩,
  .pointerDown ⟨3, 4⟩ .secondary 2 { shift := true, control := true }, .key (.char 'é') {},
  .key .pageDown { command := true }, .insertText "ü" (some (3, 4)), .setMarked "한" 0 1,
  .windowFocus false, .scale 200, .resize ⟨1, 1⟩, .scroll ⟨0, 0⟩ (-3) 5, .paste "",
  .clock ⟨18446744073709551615, -9223372036854775808, -18000⟩, .clock {},
  .reply 3 .done, .reply 4 (.bytes ⟨#[9, 8]⟩), .reply 5 (.http 404 [("Content-Type", "x")] .empty),
  .reply 6 (.failed .timeout "slow"), .subEvent 2 .tick, .subEvent 3 .changed,
  .reply 7 (.names ["a", "日本"]), .reply 8 (.names []), .reply 9 (.app 501 "Terminal"),
  .reply 10 (.flag true), .subEvent 4 (.audio 160 900 [⟨123456789012, 900⟩, ⟨0, 0⟩]),
  .subEvent 4 (.audio 0 0 []), .subEvent 5 (.keyDown 18446744073709551615), .subEvent 5 (.keyUp 0),
  .subEvent 5 (.otherKey 7), .subEvent 4 (.failed .denied "no microphone"),
  .surface 3 (.pointerDown ⟨1, 2⟩ .primary 1 {}), .surface 4294967295 .copy,
  .menuOpen 450, .menuClose 450, .menuSelect 450 ⟨453, 1⟩]

-- A surface record holds exactly one surface-local record: nesting, world and menu events
-- inside it are rejected.
#guard !fitsEvent (.surface 3 (.surface 3 .copy))
#guard (decodeEvents ⟨(Enc.eventsHeader ++ Enc.u32 1 ++ Enc.event (.surface 3 (.menuOpen 1))).toArray⟩).isNone
#guard (decodeEvents ⟨(Enc.eventsHeader ++ Enc.u32 1 ++ Enc.event (.surface 3 (.surface 3 .copy))).toArray⟩).isNone

#guard events.all fitsEvent
#guard decodeEvents (encodeEvents events) == some events
#guard decodeEvents (encodeEvents #[]) == some #[]

end Cairn.Wire.Examples

