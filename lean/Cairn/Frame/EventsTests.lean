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

private def frame : Frame where
  size := ⟨800, -600⟩
  draws := #[.rect ⟨-5, 0, 10, 10⟩ (some ⟨1, 2, 3, 4⟩) 6 none, .pushClip ⟨0, 0, 1, 1⟩,
    .text ⟨3, 4⟩ { weight := 700, italic := true } ⟨9, 9, 9, 255⟩ "日本 🙂", .popClip,
    .rect ⟨0, 0, 1, 1⟩ none 0 (some ⟨2, ⟨0, 0, 0, 255⟩⟩)]
  ax := #[axA, axB]
  textInput := some { control := ⟨2, 0⟩, rect := ⟨1, 1, 1, 1⟩, caret := ⟨2, 2, 1, 1⟩,
                      text := "ab", selection := (1, 2), marked := some (0, 1) }
  cursor := .text
  effects := #[.setClipboard "copied", .beep]

#guard fitsFrame frame
#guard reprStr (decodeFrame (encodeFrame frame)) == reprStr (some frame)
-- The compiled encoder (`Put.frame`, via `@[csimp]`) writes the specification's bytes.
#guard (encodeFrame frame).data.toList == Enc.frame frame
#guard (encodeFrame frame).size == (Enc.frame frame).length
-- Trailing bytes and a wrong version are rejected.
#guard (decodeFrame ((encodeFrame frame).push 0)).isNone
#guard (decodeFrame ((encodeFrame frame).set! 4 2)).isNone

private def events : Array Event := #[.pointerMove ⟨-1, 2⟩,
  .pointerDown ⟨3, 4⟩ .secondary 2 { shift := true, control := true }, .key (.char 'é') {},
  .key .pageDown { command := true }, .insertText "ü" (some (3, 4)), .setMarked "한" 0 1,
  .windowFocus false, .scale 200, .resize ⟨1, 1⟩, .scroll ⟨0, 0⟩ (-3) 5, .paste ""]

#guard events.all fitsEvent
#guard decodeEvents (encodeEvents events) == some events
#guard decodeEvents (encodeEvents #[]) == some #[]

end Cairn.Wire.Examples

