import Cairn.Text.Field

/-! Checks for `Cairn.Text.Field`, kept out of the module so they can use `#guard`
(a `#guard` in a `module` needs a `meta import` of what it evaluates). -/

namespace Cairn.Text

/-! ## Tests -/

namespace Tests
open Field

private def st (f : Field) : String × Nat × Nat := (f.textString, f.caret, f.anchor)
private def run (s : String) (ops : List TextOp) : Field := (ofString s).applyAll ops
private def eff (f : Field) (op : TextOp) : List Effect := (apply op f).2

-- insert
#guard st (run "" [.insert "hi"]) == ("hi", 2, 2)
#guard st (run "ac" [.setCaret 1 false, .insert "b"]) == ("abc", 2, 2)
#guard st (run "hello" [.setCaret 1 false, .setCaret 4 true, .insert "ipp"]) == ("hippo", 4, 4)
#guard st (run "" [.insert "a\nb\r\nc"]) == ("a b  c", 6, 6)
#guard st (run "" [.insert "a\u2028b\tc"]) == ("a b\tc", 5, 5)
#guard st (run "" [.insert "日本語"]) == ("日本語", 3, 3)
#guard st (run "ab" [.insert "😀"]) == ("ab😀", 3, 3)
-- deleteBackward / deleteForward
#guard st (run "abc" [.deleteBackward]) == ("ab", 2, 2)
#guard st (run "abc" [.moveHome false, .deleteBackward]) == ("abc", 0, 0)
#guard st (run "abc" [.selectAll, .deleteBackward]) == ("", 0, 0)
#guard st (run "abc" [.setCaret 1 false, .deleteForward]) == ("ac", 1, 1)
#guard st (run "abc" [.deleteForward]) == ("abc", 3, 3)
#guard st (run "abcd" [.setCaret 1 false, .setCaret 3 true, .deleteForward]) == ("ad", 1, 1)
-- word deletion
#guard st (run "hello big world" [.deleteWordBackward]) == ("hello big ", 10, 10)
#guard st (run "hello big world  " [.deleteWordBackward]) == ("hello big ", 10, 10)
#guard st (run "hello, world" [.moveHome false, .deleteWordForward]) == (", world", 0, 0)
#guard st (run "hello, world" [.setCaret 5 false, .deleteWordForward]) == ("hello", 5, 5)
#guard st (run "foo bar" [.setCaret 0 false, .setCaret 2 true, .deleteWordBackward]) == ("o bar", 0, 0)
-- character movement
#guard st (run "abc" [.moveLeft false]) == ("abc", 2, 2)
#guard st (run "abc" [.moveLeft true, .moveLeft true]) == ("abc", 1, 3)
#guard st (run "abc" [.moveLeft true, .moveLeft true, .moveLeft false]) == ("abc", 1, 1)
#guard st (run "abc" [.moveHome false, .moveLeft false]) == ("abc", 0, 0)
#guard st (run "abc" [.moveRight false]) == ("abc", 3, 3)
#guard st (run "abc" [.moveHome false, .moveRight true, .moveRight true]) == ("abc", 2, 0)
#guard st (run "abc" [.moveHome false, .moveRight true, .moveRight true, .moveRight false]) ==
  ("abc", 2, 2)
-- word movement
#guard st (run "one two  three" [.moveWordLeft false]) == ("one two  three", 9, 9)
#guard st (run "one two  three" [.moveWordLeft false, .moveWordLeft false]) ==
  ("one two  three", 4, 4)
#guard st (run "one two" [.moveHome false, .moveWordRight false]) == ("one two", 3, 3)
#guard st (run "one two" [.moveHome false, .moveWordRight true, .moveWordRight true]) ==
  ("one two", 7, 0)
#guard st (run "a.b" [.moveWordLeft false]) == ("a.b", 2, 2)
#guard st (run "café au lait" [.moveHome false, .moveWordRight false]) == ("café au lait", 4, 4)
#guard st (run "one two three" [.setCaret 4 false, .setCaret 7 true, .moveWordLeft false]) ==
  ("one two three", 0, 0)
-- line movement
#guard st (run "abc" [.moveHome false]) == ("abc", 0, 0)
#guard st (run "abc" [.moveHome true]) == ("abc", 0, 3)
#guard st (run "abc" [.moveHome false, .moveEnd true]) == ("abc", 3, 0)
-- setCaret, selectAll
#guard st (run "abc" [.setCaret 99 false]) == ("abc", 3, 3)
#guard st (run "abcd" [.setCaret 1 false, .setCaret 3 true]) == ("abcd", 3, 1)
#guard st (run "abc" [.selectAll]) == ("abc", 3, 0)
#guard (run "abc" [.setCaret 1 false, .setCaret 3 true]).selected == ['b', 'c']
-- cut, copy, paste
#guard eff (run "hello" [.setCaret 1 false, .setCaret 4 true]) .copy == [.setClipboard "ell"]
#guard eff (run "hello" []) .copy == []
#guard (apply .copy (run "hello" [.selectAll])).1 == run "hello" [.selectAll]
#guard eff (run "hello" [.setCaret 1 false, .setCaret 4 true]) .cut == [.setClipboard "ell"]
#guard st (run "hello" [.setCaret 1 false, .setCaret 4 true, .cut]) == ("ho", 1, 1)
#guard st (run "hello" [.cut]) == ("hello", 5, 5)
#guard st (run "hello" [.selectAll, .paste "bye\nnow"]) == ("bye now", 7, 7)
#guard st (run "ab" [.moveLeft false, .paste "XY"]) == ("aXYb", 3, 3)
-- undo / redo, with typing coalesced into one step
#guard st (run "" [.insert "a", .insert "b", .insert "c", .undo]) == ("", 0, 0)
#guard st (run "" [.insert "a", .insert "b", .undo, .redo]) == ("ab", 2, 2)
#guard st (run "" [.insert "ab", .moveLeft false, .insert "x", .undo]) == ("ab", 1, 1)
#guard st (run "" [.insert "ab", .moveLeft false, .insert "x", .undo, .undo]) == ("", 0, 0)
#guard st (run "abc" [.deleteBackward, .deleteBackward, .undo]) == ("abc", 3, 3)
#guard st (run "" [.insert "a", .insert "b", .deleteBackward, .undo]) == ("", 0, 0)
#guard st (run "" [.insert "a", .insert "b", .deleteBackward, .insert "c", .undo]) == ("", 0, 0)
#guard st (run "abc" [.insert "d", .moveLeft false, .deleteBackward, .undo]) == ("abcd", 3, 3)
#guard st (run "ab cd" [.insert "e", .deleteWordBackward, .undo]) == ("ab cde", 6, 6)
#guard st (run "abc" [.selectAll, .deleteBackward, .undo]) == ("abc", 3, 0)
#guard st (run "abc" [.selectAll, .insert "x", .insert "y", .undo]) == ("abc", 3, 0)
#guard st (run "hello" [.setCaret 1 false, .setCaret 4 true, .cut, .undo]) == ("hello", 4, 1)
#guard st (run "ab" [.paste "c", .paste "d", .undo]) == ("abc", 3, 3)
#guard st (run "a" [.insert "b", .undo, .insert "c", .redo]) == ("ac", 2, 2)
#guard eff (run "a" []) .undo == [.beep]
#guard eff (run "a" [.insert "b"]) .redo == [.beep]
#guard eff (run "a" [.insert "b"]) .undo == []
-- IME: k → か, then commit
#guard (run "" [.setMarked "k" 1 0]).marked == some (0, 1)
#guard st (run "" [.setMarked "k" 1 0]) == ("k", 1, 1)
#guard st (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0]) == ("か", 1, 1)
#guard (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0]).marked == some (0, 1)
#guard st (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0, .unmark]) == ("か", 1, 1)
#guard (run "" [.setMarked "k" 1 0, .setMarked "か" 1 0, .unmark]).marked == none
-- composing inside existing text, with the IME's selection inside the marked text
#guard st (run "ab" [.moveLeft false, .setMarked "にほ" 0 2]) == ("aにほb", 3, 1)
#guard (run "ab" [.moveLeft false, .setMarked "にほ" 0 2]).marked == some (1, 3)
#guard st (run "ab" [.moveLeft false, .setMarked "にほ" 2 0, .insert "日本"]) == ("a日本b", 3, 3)
#guard (run "ab" [.moveLeft false, .setMarked "にほ" 2 0, .insert "日本"]).marked == none
-- composition replaces a selection; the whole composition is one undo step
#guard st (run "xyz" [.selectAll, .setMarked "k" 1 0, .setMarked "か" 1 0, .unmark]) ==
  ("か", 1, 1)
#guard st (run "xyz" [.selectAll, .setMarked "k" 1 0, .setMarked "か" 1 0, .unmark, .undo]) ==
  ("xyz", 3, 0)
#guard st (run "a" [.setMarked "k" 1 0, .setMarked "か" 1 0, .insert "か", .undo]) == ("a", 1, 1)
-- an empty composition ends it and restores the text before it
#guard st (run "a" [.setMarked "k" 1 0, .setMarked "" 0 0]) == ("a", 1, 1)
#guard (run "a" [.setMarked "k" 1 0, .setMarked "" 0 0]).marked == none
-- movement ends a composition, keeping its text
#guard st (run "a" [.setMarked "k" 1 0, .moveLeft false]) == ("ak", 1, 1)
#guard (run "a" [.setMarked "k" 1 0, .moveLeft false]).marked == none
-- replacement ranges from the input system (not yet in `TextOp`; see docs/text.md)
#guard st ((run "abe" []).insert "è" (some (2, 3))) == ("abè", 3, 3)
#guard st (((run "ab" []).setMarked "에" 1 0 (some (1, 2)))) == ("a에", 2, 2)
#guard st ((run "ab" []).insert "x" (some (5, 9))) == ("abx", 3, 3)
#guard st ((run "abc" []).insert "x" (some (2, 1))) == ("axbc", 2, 2)
-- view
#guard (run "hi" [.moveLeft true]).view true ==
  { text := "hi", caret := 1, anchor := 2, focused := true }
#guard (empty "What needs to be done?").view false ==
  { text := "", caret := 0, anchor := 0, placeholder := "What needs to be done?" }

end Tests


end Cairn.Text
