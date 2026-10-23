import Cairn.Frame.Build

/-! Checks for `Cairn.Frame.Build`, kept out of the module so they can use `#guard`
(a `#guard` in a `module` needs a `meta import` of what it evaluates). -/

namespace Cairn

/-! ## Examples -/

namespace Frame.Examples

private def button : Control := { ref := ⟨1, 0⟩, label := "Add" }
private def field : Control := { ref := ⟨2, 0⟩, role := .textField, label := "New todo" }
private def win : Rect := ⟨0, 0, 400, 300⟩

/-- A clipping column holding a button with a label and a focused field. -/
private def sample : Laid :=
  .box win win { clip := true, background := some ⟨255, 255, 255, 255⟩ } none [
    .box ⟨10, 10, 80, 24⟩ win { background := some ⟨0, 0, 255, 255⟩ } (some button) [
      .text ⟨20, 14, 30, 16⟩ win 27 {} "Add"],
    .field ⟨10, 40, 200, 24⟩ win {} {} field { text := "héllo", caret := 5, anchor := 2 }
      ⟨14, 57⟩ ⟨44, 44, 1, 16⟩ [⟨24, 44, 20, 16⟩]]

private def f := ofLaid { focus := some ⟨2, 0⟩ } sample

#guard f.draws.size == 9
#guard f.draws[0]! == .rect win (some ⟨255, 255, 255, 255⟩) 0 none
#guard f.draws[1]! == .pushClip win
#guard f.draws[3]! == .text ⟨20, 27⟩ {} ⟨0, 0, 0, 255⟩ "Add"
#guard f.draws.back! == .popClip
#guard f.ax.map (·.role) == #[.button, .text, .textField]
#guard f.ax.map (·.parent) == #[none, some 0, none]
#guard f.ax[2]!.value == "héllo" && f.ax[2]!.focused
#guard (f.textInput.map (·.selection)) == some (2, 5)
-- No caret while there is a selection; a caret once it collapses.
#guard !(f.draws.contains (.rect ⟨44, 44, 1, 16⟩ (some ⟨0, 0, 0, 255⟩) 0 none))
#guard (ofLaid { focus := none } sample).textInput.isNone
#guard (f.textInput.map (·.textOrigin)) == some ⟨14, 57⟩

end Frame.Examples


end Cairn
