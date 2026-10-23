import Cairn.Fuzz.Rng

/-! # The default text generator

Scripts of `TextOp`s for a field's `edit` moves. Each operation in a script is sent as its own
event, the way a person's typing arrives. The pool leans on what breaks text code: blanks,
emoji with skin tones and ZWJ sequences, flags, combining marks, CJK, long strings, and IME
compositions (`setMarked` one to three times, then a committing `insert` or an `unmark`). -/

namespace Cairn.Fuzz.Text
open Cairn

def samples : List String :=
  [ "milk", "eggs", "a", "Hello world", "  padded  ", " ", "   ", "\t", "x y z",
    "é", "ä́", "👍🏽", "👨‍👩‍👧", "🇫🇷", "日本語", "Ünïcödé", "😀😀",
    String.ofList (List.replicate 60 'w') ]

/-- IME compositions: the marked prefixes, and what commits. -/
def compositions : List (List String × String) :=
  [ (["に", "にほ", "にほん"], "日本"), (["か", "かな"], "仮名"), (["ㅎ", "하", "한"], "한"),
    (["´"], "é"), (["n", "ni"], "に") ]

def ime : Gen (List TextOp) := do
  let (marks, commit) ← Gen.elem compositions
  let k ← Gen.range 1 marks.length
  let steps := (marks.take k).map fun m => TextOp.setMarked m m.length 0
  let last ← Gen.weighted [(3, pure (TextOp.insert commit)), (1, pure TextOp.unmark)]
  return steps ++ [last]

/-- One script of text operations. -/
def script : Gen (List TextOp) :=
  Gen.weighted
    [ (30, do return [.insert (← Gen.elem samples)]),
      (10, do return [← Gen.elem [.deleteBackward, .deleteForward]]),
      (4, do return [← Gen.elem [.deleteWordBackward, .deleteWordForward]]),
      (8, do let e ← Gen.bool; return [← Gen.elem [.moveLeft e, .moveRight e]]),
      (4, do let e ← Gen.bool; return [← Gen.elem [.moveWordLeft e, .moveWordRight e]]),
      (4, do let e ← Gen.bool; return [← Gen.elem [.moveHome e, .moveEnd e]]),
      (3, pure [.selectAll]),
      (4, do return [← Gen.elem [.copy, .cut]]),
      (3, do return [.paste (← Gen.elem samples)]),
      (6, do return [← Gen.elem [.undo, .undo, .redo]]),
      (6, ime) ]

end Cairn.Fuzz.Text
