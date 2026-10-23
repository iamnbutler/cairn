import Cairn.Layout.Proofs

/-! Concrete checks of `layout` with the mono metrics (13 pt: 7 points per scalar, ascent 10,
descent 2, so a line is 12 high). These fail fast when a definition is wrong, before any proof
is attempted. -/

namespace Cairn.Layout.Tests
open Cairn

private def m := TextMetrics.mono
private def win : Size := ⟨200, 100⟩
private def rects (l : Laid) : List Rect := l.children.map Laid.rect
private def ctl (k : Nat) : Control := { ref := ⟨k, 0⟩, label := s!"c{k}" }
private def fixedBox (w h : Nat) : Node := .box { width := .fixed w, height := .fixed h } none []
private def fillBox : Node := .box { width := .fill, height := .fill } none []

-- Text: its rect is its measured box; the baseline is the ascent below its top.
#guard (layout m win (.text {} "abc")).rect == ⟨0, 0, 21, 12⟩
#guard match layout m win (.text {} "abc") with | .text _ _ b .. => b == 10 | _ => false

-- A row places children left to right with padding and gaps; hug sizes the row to fit.
private def row1 : Node :=
  .box { axis := .row, gap := 4, padding := ⟨1, 2, 3, 5⟩ } none [fixedBox 10 6, fixedBox 20 8]
#guard (layout m win row1).rect == ⟨0, 0, 5 + 10 + 4 + 20 + 2, 1 + 8 + 3⟩
#guard rects (layout m win row1) == [⟨5, 1, 10, 6⟩, ⟨19, 1, 20, 8⟩]

-- Fill children share leftover space exactly; the remainder goes to the later ones.
private def fills : Node :=
  .box { axis := .row, width := .fixed 100 } none [fillBox, fillBox, fillBox]
#guard rects (layout m win fills) == [⟨0, 0, 33, 0⟩, ⟨33, 0, 33, 0⟩, ⟨66, 0, 34, 0⟩]

-- A fill child takes what fixed siblings and gaps leave.
private def toolbar : Node :=
  .box { axis := .row, width := .fill, height := .fixed 30, gap := 10 } none
    [fixedBox 40 30, fillBox, fixedBox 40 30]
#guard rects (layout m win toolbar) == [⟨0, 0, 40, 30⟩, ⟨50, 0, 100, 30⟩, ⟨160, 0, 40, 30⟩]

-- Cross-axis alignment in a row 30 high.
private def aligned (al : Align) : Node :=
  .box { axis := .row, height := .fixed 30, align := al } none [fixedBox 10 10, .box {} none []]
#guard rects (layout m win (aligned .start)) == [⟨0, 0, 10, 10⟩, ⟨10, 0, 0, 0⟩]
#guard rects (layout m win (aligned .center)) == [⟨0, 10, 10, 10⟩, ⟨10, 15, 0, 0⟩]
#guard rects (layout m win (aligned .finish)) == [⟨0, 20, 10, 10⟩, ⟨10, 30, 0, 0⟩]
-- Stretch stretches hug children only, never fixed ones.
#guard rects (layout m win (aligned .stretch)) == [⟨0, 0, 10, 10⟩, ⟨10, 0, 0, 30⟩]
-- Text is never stretched.
#guard rects (layout m win (.box { axis := .row, height := .fixed 30, align := .stretch } none
    [.text {} "a"])) == [⟨0, 0, 7, 12⟩]

-- Main-axis justification in a column 100 high with 10 + 4 + 10 used.
private def justified (j : Align) : Node :=
  .box { height := .fixed 100, gap := 4, justify := j } none [fixedBox 10 10, fixedBox 10 10]
#guard rects (layout m win (justified .start)) == [⟨0, 0, 10, 10⟩, ⟨0, 14, 10, 10⟩]
#guard rects (layout m win (justified .center)) == [⟨0, 38, 10, 10⟩, ⟨0, 52, 10, 10⟩]
#guard rects (layout m win (justified .finish)) == [⟨0, 76, 10, 10⟩, ⟨0, 90, 10, 10⟩]
-- Stretch is space-between: first at the start, last at the end.
#guard rects (layout m win (justified .stretch)) == [⟨0, 0, 10, 10⟩, ⟨0, 90, 10, 10⟩]

-- Overflow: children keep their sizes and run past the end; fill children get nothing.
private def over : Node :=
  .box { axis := .row, width := .fixed 30 } none [fixedBox 20 5, fillBox, fixedBox 20 5]
#guard rects (layout m win over) == [⟨0, 0, 20, 5⟩, ⟨20, 0, 0, 5⟩, ⟨20, 0, 20, 5⟩]

-- A stack overlays children in its content box: justify places x, align places y.
private def stack : Node :=
  .box { axis := .stack, width := .fixed 50, height := .fixed 40, justify := .center,
         align := .finish } none [fixedBox 10 10, fillBox]
#guard rects (layout m win stack) == [⟨20, 30, 10, 10⟩, ⟨0, 0, 50, 40⟩]

-- The root's fill takes the window; its clip is the window.
#guard (layout m win (.box { width := .fill, height := .fill } none [])).rect == ⟨0, 0, 200, 100⟩
#guard (layout m win fillBox).clip == ⟨0, 0, 200, 100⟩
#guard (layout m ⟨-5, 10⟩ fillBox).clip == ⟨0, 0, 0, 10⟩

-- Clipping: children of a clipping box paint within its rect.
private def clipped : Node :=
  .box { axis := .row, width := .fixed 30, height := .fixed 10, padding := ⟨0, 0, 0, 25⟩,
         clip := true } none [fixedBox 20 5]
#guard (layout m win clipped).children.map Laid.clip == [⟨0, 0, 30, 10⟩]
#guard (layout m win clipped).children.map Laid.visible == [⟨25, 0, 5, 5⟩]
-- Disjoint clips leave an empty clip inside the parent's.
#guard (Rect.inter ⟨0, 0, 10, 10⟩ ⟨50, 50, 5, 5⟩) == ⟨10, 10, 0, 0⟩

-- Fields: hug width is the text plus a point for the caret; the caret sits at its offset.
private def fld (text : String) (caret anchor : Nat) (w : Sizing := .hug) : Node :=
  .field { width := w, padding := ⟨2, 3, 2, 3⟩ } {} (ctl 9)
    { text, caret, anchor, placeholder := "Search" }
#guard (layout m win (fld "hi" 1 1)).rect == ⟨0, 0, 3 + 14 + 1 + 3, 2 + 12 + 2⟩
-- An empty field hugs its placeholder.
#guard (layout m win (fld "" 0 0)).rect == ⟨0, 0, 3 + 42 + 1 + 3, 16⟩
#guard match layout m win (fld "hi" 1 1) with
  | .field _ _ _ _ _ _ o caret sel => o == ⟨3, 12⟩ && caret == ⟨10, 2, 1, 12⟩ && sel.isEmpty
  | _ => false
-- A selection from anchor 0 to caret 2.
#guard match layout m win (fld "hello" 2 0) with
  | .field _ _ _ _ _ _ _ _ sel => sel == [⟨3, 2, 14, 12⟩]
  | _ => false
-- A long text scrolls so the caret at the end stays inside the 20-point content box.
#guard match layout m win (fld "hello world" 11 11 (.fixed 26)) with
  | .field _ _ _ _ _ _ o caret _ => caret == ⟨3 + 19, 2, 1, 12⟩ && o.x == 3 + 19 - 77
  | _ => false

-- Controls come out in paint order: a node before its children.
private def withControls : Node :=
  .box { axis := .row } (some (ctl 1))
    [.box {} (some (ctl 2)) [.text {} "x"], fld "" 0 0, .box {} (some (ctl 3)) []]
#guard ((layout m win withControls).controls.map (·.ref.claim)) == [1, 2, 9, 3]

-- The theorems apply to these trees too.
example : (layout m win withControls).controls = withControls.controls := layout_controls m win _
example : Facts m win toolbar (layout m win toolbar) := facts TextMetrics.mono_valid win toolbar

end Cairn.Layout.Tests
