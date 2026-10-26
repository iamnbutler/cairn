import Fixture
import Cairn.Runtime
import Cairn.Frame.Dump

/-! Runtime checks for the fixture: events in, through layout, hit testing, focus, timers and
the v1 boundary, with mono metrics (the interpreter can't call the host's Core Text). -/

namespace Fixture.Tests
open Cairn Cairn.Runtime Fixture

def tcfg : Config := {}
def run (es : List Event) : Runtime.State State := (steps app tcfg (start app tcfg ⟨480, 600⟩) es).1
def st (es : List Event) : State := (run es).app
def texts (s : State) : List (Nat × String × Bool) := s.items.map fun i => (i.id, i.text, i.done)

def at? (rs : Runtime.State State) (r : ControlRef) : Option Point :=
  (find rs.laid r).map (·.visible.center)
/-- Not in the list: one of its rows (`^10#k`) or its end line (^16). -/
def notRow (r : ControlRef) : Bool := r.claim != 10 && r.claim != 16

def clickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
  | none => []

-- region: fixture-tests
def typed : List Event :=
  clickOn (run []) fieldRef ++ [.insertText "  milk ", .key .enter {}, .insertText "eggs"]
def two : List Event := typed ++ clickOn (run typed) addRef

#guard texts (st typed) == [(1, "milk", false)]
#guard texts (st two) == [(1, "milk", false), (2, "eggs", false)]
def toggled : List Event := two ++ clickOn (run two) (toggleRef 1)
#guard texts (st toggled) == [(1, "milk", true), (2, "eggs", false)]
#guard left (st toggled) == 1
def deleted : List Event := toggled ++ clickOn (run toggled) (deleteRef 2)
#guard texts (st deleted) == [(1, "milk", true)]
/-- The buttons under Flash: Top, End, Go to row, Hide rows, then Badge, Clear badge, Announce. -/
def moreRefs : List ControlRef :=
  [topRef, endButtonRef, goRowRef, hideRef, badgeRef, clearBadgeRef, announceRef]
-- Tab order: field, Add, Passcode, Flash, Add above, Add below, the buttons under them, then each
-- item's checkbox, delete button and ⋯, the posts' Like buttons and Refresh (and then the list's
-- rows, `notRow`).
#guard ((tabOrder (run two).laid).map (·.ref)).filter notRow ==
  [fieldRef, addRef, passRef, flashRef, addTopRef, addEndRef] ++ moreRefs ++
  [toggleRef 1, deleteRef 1, moreRef 1, toggleRef 2, deleteRef 2, moreRef 2, likeRef 1, likeRef 2,
   likeRef 3, likeRef 4, refreshRef]
-- Flash sets its timer; the note shows until it fires.
def flashed : List Event := clickOn (run []) flashRef
#guard (st flashed).flash
-- The frame through the v1 boundary carries the keyed controls.
#guard ((decodeFrame (frameBytes Frame.boundary (run two))).map fun f =>
  (f.ax.toList.filterMap (·.control)).filter notRow) ==
  some ([fieldRef, addRef, passRef, flashRef, addTopRef, addEndRef] ++ moreRefs ++
        [toggleRef 1, deleteRef 1, moreRef 1, toggleRef 2, deleteRef 2, moreRef 2, likeRef 1,
         likeRef 2, likeRef 3, likeRef 4, refreshRef])
-- endregion: fixture-tests

-- region: fixture-menu-tests
-- Menus on controls (docs/surfaces.md): the ⋯ button opens on a click, the checkbox on a
-- secondary click; the window record carries the open menu; choosing an item presses it, and a
-- greyed one does nothing. Opening changes no app state.
def win : ClaimId := 1
def rightClickOn (rs : Runtime.State State) (r : ControlRef) : List Event :=
  match at? rs r with
  | some p => [.pointerMove p, .pointerDown p .secondary 1 {}, .pointerUp p .secondary {}]
  | none => []
def opened : List Event := two ++ clickOn (run two) (moreRef 1)
#guard (run opened).ui.menu == some (moreRef 1)
#guard st opened == st two
#guard ((decodeFrame (frameBytes Frame.boundary (run opened))).map fun f =>
  (f.ax.toList.filter (·.control == some (moreRef 1))).map (·.menu)) == some [some true]
def chosen : List Event := opened ++ [.menuSelect win (menuToggleRef 1), .menuClose win]
#guard texts (st chosen) == [(1, "milk", true), (2, "eggs", false)]
#guard (run chosen).ui.menu == none
-- Delete is greyed for an item not done: choosing it does nothing.
#guard st (opened ++ [.menuSelect win (menuDeleteRef 1)]) == st opened
-- The checkbox's secondary click opens the same menu; Delete is enabled once the item is done.
def ctx : List Event := chosen ++ rightClickOn (run chosen) (toggleRef 1)
#guard (run ctx).ui.menu == some (toggleRef 1)
#guard texts (st (ctx ++ [.menuSelect win (menuDeleteRef 1)])) == [(2, "eggs", false)]
-- A choice from a menu that isn't open does nothing.
#guard st (two ++ [.menuSelect win (menuToggleRef 1)]) == st two
-- The keyboard: Shift-F10 (`Key.menu`) on the focused checkbox, Space on the focused ⋯ button.
def tabbed (n : Nat) : List Event := two ++ List.replicate n (.key .tab {})
#guard (run (tabbed 14 ++ [.key .menu {}])).ui.menu == some (toggleRef 1)
#guard (run (tabbed 16 ++ [.key (.char ' ') {}])).ui.menu == some (moreRef 1)
-- The menu bar: Clear Done and Go ▸ First Row / No Row, by `menuSelect` with its place.
#guard (st (toggled ++ [.menuSelect 28 clearDoneRef])).items.map (·.id) == [2]
#guard (st (two ++ [.menuSelect 28 firstRowRef])).selected == some 1
#guard (st (two ++ [.menuSelect 28 noRowRef])) == st two
-- endregion: fixture-menu-tests

-- The Passcode field: bullets on screen, nothing in the accessibility value, a redacted request.
def secret : List Event := clickOn (run []) passRef ++ [.insertText "hunter2"]
#guard (st secret).passcode.text == "hunter2"
#guard ((decodeFrame (frameBytes Frame.boundary (run secret))).map fun f =>
  (f.ax.toList.filter (·.control == some passRef)).map fun n => (n.value, n.secure)) ==
  some [("", true)]
#guard !Dump.occurs "hunter2" (Dump.canvas (Frame.ofLaid (run secret).ui (run secret).laid))
#guard (steps app tcfg (run secret) [.key .enter {}]).2.any fun
  | .request _ r => r.redact && !Dump.occurs "hunter2" (Dump.request r)
  | _ => false
#guard (st (secret ++ [.key .enter {}])).passcode.len == 0

-- region: fixture-scroll-tests
-- The list: 10,000 rows of 24 to 48 points (row k is 24 + 8·(k mod 4)) and the end line, in a box
-- 160 high. It opens at the top, and lays only the rows that meet the box widened by 200 points
-- above and below: rows 1 to 10 (360 points).
def box : Rect := ((run []).laid.children.getD 8 default).rect
def rectIn (rs : Runtime.State State) (k : Nat) : Option Rect := (find rs.laid (rowRef k)).map (·.node.rect)
def rectOf (es : List Event) (k : Nat) : Option Rect := rectIn (run es) k
def click (p : Point) : List Event := [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}]
def offset (es : List Event) : Int := (run es).ui.scrollOf rowsRef
/-- The rows the list laid: their keys. -/
def laidKeys (es : List Event) : List Nat :=
  ((targets (run es).laid).map (·.ref)).filterMap fun r => if r.claim = 10 then some r.key else none
/-- Each laid row starts where the one before it ends. -/
def stacked (es : List Event) : Bool :=
  let rs := (laidKeys es).filterMap (rectOf es)
  (rs.zip (rs.drop 1)).all fun (a, b) => b.y == a.y + a.h

#guard box.h == 160
#guard offset [] == 0
#guard laidKeys [] == List.range' 1 10
#guard rectOf [] 1 == some ⟨box.x, box.y, box.w, 32⟩
#guard rectOf [] 2 == some ⟨box.x, box.y + 32, box.w, 40⟩
#guard stacked []
-- A wheel tick of 1,616 points: the runtime lays rows 40 to 55, records their heights, and keeps
-- the first row showing (46) still as estimates turn into heights, which moves the offset to
-- 1,604. The app hears nothing of it.
def down : List Event := [.scroll box.center 0 1616]
#guard offset down == 1604
#guard laidKeys down == List.range' 40 16
#guard stacked down
#guard rectOf down 46 == some ⟨box.x, box.y, box.w, 40⟩
#guard st down == st []
-- A click on a row selects it, and it grows to 72 points: the rows under it move down, the
-- first showing stays.
def sel : List Event := down ++ ((rectOf down 47).map (click ·.center) |>.getD [])
#guard (st sel).selected == some 47
#guard rectOf sel 47 == some ⟨box.x, box.y + 40, box.w, 72⟩
#guard rectOf sel 48 == some ⟨box.x, box.y + 112, box.w, 24⟩
#guard rectOf sel 46 == rectOf down 46
#guard stacked sel
-- A row added at the top, while scrolled: every row on screen stays where it was.
def addAbove : List Event := down ++ clickOn (run down) addTopRef
#guard (st addAbove).keys[0]? == some 10001
#guard (List.range' 40 16).all fun k => rectOf addAbove k == rectOf down k
-- At the top too: row 1 stays at the top of the box, and the new row is just above it.
def addAbove0 : List Event := clickOn (run []) addTopRef
#guard offset addAbove0 == 32
#guard rectOf addAbove0 1 == rectOf [] 1
#guard rectOf addAbove0 10001 == some ⟨box.x, box.y - 32, box.w, 32⟩
-- A row added at the end goes above the end line.
#guard ((st (clickOn (run []) addEndRef)).keys.toList.drop 10000) == [10001, 0]
-- Far past the end: clamped to the end, where the end line shows and ^16 counts it, once per
-- visit. The content's length is an estimate until the rows are laid.
def far : List Event := [.scroll box.center 0 10000000]
#guard laidKeys far == List.range' 9991 10
#guard (find (run far).laid endRef).map (fun t => t.node.rect.y + t.node.rect.h) == some (box.y + box.h)
#guard (st far).ends == 1
#guard (st (far ++ [.scroll box.center 0 (-10)])).ends == 1
#guard (st down).ends == 0
#guard (((steps app tcfg (run far) [.scroll box.center 0 (-10000000)]).1 |>
  fun r => steps app tcfg r [.scroll box.center 0 10000000]).1.app.ends) == 2
#guard offset (far ++ [.scroll box.center 0 (-20000000)]) == 0
-- Keys move the box under the pointer: a page is the box less a line (120), End goes to the end.
#guard offset [.pointerMove box.center, .key .pageDown {}] == 120
#guard offset [.pointerMove box.center, .key .finish {}] == offset far
#guard offset [.pointerMove box.center, .key .finish {}, .key .home {}] == 0
-- Tab reaches only the rows laid: shift-Tab from nothing goes to the last of them.
#guard (run [.key .tab { shift := true }]).ui.focus == some (rowRef 10)
-- The frame names only the rows laid, draws only the five that show (rows 1 to 5 at the top),
-- and gives the box a node of its own.
def frame0 : Option Frame := decodeFrame (frameBytes Frame.boundary (run []))
#guard (frame0.map fun f => ((f.ax.toList.filterMap (·.control)).filter (·.claim == 10)).length) == some 10
#guard (frame0.map fun f => (f.draws.toList.filter fun
  | .text _ _ _ t => t.startsWith "Row " | _ => false).length) == some 5
#guard (frame0.map fun f => (f.ax.toList.filter (·.role == .scrollArea)).length) == some 1
-- `scrollTo` (#234): End lands where scrolling far past the end does; Go to row puts row 5,000
-- at the top of the box; Top goes back to 0.
def toEnd : List Event := clickOn (run []) endButtonRef
#guard offset toEnd == offset far
#guard laidKeys toEnd == List.range' 9991 10
def toRow : List Event := clickOn (run []) goRowRef
#guard rectOf toRow 5000 == some ⟨box.x, box.y, box.w, 24⟩
#guard offset (down ++ clickOn (run down) topRef) == 0
-- Hidden, the list lays nothing but keeps its offset and heights (`keepScroll`); shown again,
-- it comes back where it was.
def hid : List Event := down ++ clickOn (run down) hideRef
#guard laidKeys hid == []
#guard offset hid == offset down
def shown : List Event := hid ++ clickOn (run hid) hideRef
#guard offset shown == offset down
#guard laidKeys shown == laidKeys down
#guard (List.range' 40 16).all fun k => rectOf shown k == rectOf down k
-- Badge, Clear badge and Announce hand the host one effect each.
def badged : List Event := clickOn (run []) badgeRef
#guard (steps app tcfg (run []) badged).2.any fun | .badge (some "1") => true | _ => false
#guard (steps app tcfg (run badged) (clickOn (run badged) clearBadgeRef)).2.any fun
  | .badge none => true | _ => false
#guard (steps app tcfg (run []) (clickOn (run []) announceRef)).2.any fun
  | .announce "Announcement 1" .high => true | _ => false
-- endregion: fixture-scroll-tests

-- region: fixture-vlist-settle-tests
/-! Two virtual-list regressions, each on a small app of its own (not the fixture's claims).
`settledFrame`: every row a list laid is at the height the view laid it out by (the fuzzer's
`vlist` check); `topIn`: a row's top in the list's box. -/
section VListRegressions

def listRef : ControlRef := ⟨900, 0⟩
def btnA : ControlRef := ⟨901, 0⟩
def btnB : ControlRef := ⟨902, 0⟩
def lineRef (k : Nat) : ControlRef := ⟨903, k⟩

/-- A row: `h` points high; marked `appear` when `ap`. -/
def line (k h : Nat) (ap : Bool := false) : Node :=
  .box { width := .fill, height := .fixed h }
    (some { ref := lineRef k, role := .text, label := s!"Line {k}", appear := ap }) []

/-- Every row each list in `rs` laid is at the height the view laid the list out by. -/
def settledFrame {S : Type} (rs : Runtime.State S) : Bool :=
  (listsOf rs.laid).all fun ll =>
    (VList.laidRows ll.info ll.kids).all fun r => (r.height : Int) == ll.info.modelOf.height r.index

/-- Row `k`'s top less the top of the list's box, if it is laid. -/
def topIn {S : Type} (rs : Runtime.State S) (k : Nat) : Option Int :=
  match (listsOf rs.laid).find? (·.ref == listRef), find rs.laid (lineRef k) with
  | some ll, some t => some (t.node.rect.y - ll.rect.y)
  | _, _ => none

def offOf {S : Type} (rs : Runtime.State S) : Int := rs.ui.scrollOf listRef

def clickAt {S : Type} (rs : Runtime.State S) (r : ControlRef) : List Event :=
  match find rs.laid r with
  | some t => click t.visible.center
  | none => []

/-! ### Many rows shrink at once (#276)

400 rows of 100 points in a 300-point box. Shrink makes every row 1 point (a filter hiding
them, as a mute does in Sky): each layout lays the next window of rows the runtime still knows
at 100 points, so the list takes far more layouts than `settleFuel` to settle. -/

structure Shrink where
  small : Bool := false
deriving Inhabited

def shrinkKeys : Array Nat := Array.range' 1 400

def shrinkView (s : Shrink) (ui : UI) : Node :=
  .box { width := .fill, height := .fill } none
    [ button ui btnA "Shrink",
      VList.node { ref := listRef, style := { width := .fill, height := .fixed 300 } } ui
        shrinkKeys fun k => line k (if s.small then 1 else 100) ]

def shrinkApp : App Shrink :=
  { init := {}, surfaces := [.window 1 "Shrink" shrinkView], claims := [],
    update := fun s a => (if a == .press btnA then { s with small := !s.small } else s, []) }

def s0 : Runtime.State Shrink := start shrinkApp tcfg ⟨480, 600⟩
def s1 : Runtime.State Shrink := (steps shrinkApp tcfg s0 (clickAt s0 btnA)).1
#guard settledFrame s0 && topIn s0 2 == some 100
-- Every row laid at its height, 1 point: the frame isn't laid by heights the list no longer has.
#guard s1.app.small && settledFrame s1 && topIn s1 2 == some 1

/-! ### A clamp within a batch (#271)

Three rows of 30 points in a 100-point box: the list fits, at offset 0, with row 1 at the top.
Add puts a row above them, which the reader would scroll past (offset 30) but the clamp holds
at 20 (the limit), so the new row shows 10 points of itself and hears `appear`. Hearing it
loads three more rows at the end, in the same batch: now the offset can go to 30, and row 1 is
back at the top of the box where the reader last saw it. -/

structure Clamp where
  keys : Array Nat := #[1, 2, 3]
  loaded : Bool := false
  /-- The box is 200 high instead of 100. -/
  tall : Bool := false
deriving Inhabited

def clampView (s : Clamp) (ui : UI) : Node :=
  .box { width := .fill, height := .fill } none
    [ .box { axis := .row, gap := 8 } none [button ui btnA "Add", button ui btnB "Tall"],
      VList.node { ref := listRef, overscan := 0,
                   style := { width := .fill, height := .fixed (if s.tall then 200 else 100) } } ui
        s.keys fun k => line k 30 (ap := k == 100) ]

def clampUpdate (s : Clamp) : Action → Clamp
  | .press r =>
    if r == btnA then { s with keys := #[100] ++ s.keys }
    else if r == btnB then { s with tall := !s.tall } else s
  | .appear r =>
    if r == lineRef 100 && !s.loaded then { s with keys := s.keys ++ #[4, 5, 6], loaded := true }
    else s
  | _ => s

def clampApp : App Clamp :=
  { init := {}, surfaces := [.window 1 "Clamp" clampView], claims := [],
    update := fun s a => (clampUpdate s a, []) }

/-- A batch on `rs`: a click on `r`, then the frame shown. -/
def clampClick (rs : Runtime.State Clamp) (r : ControlRef) : Runtime.State Clamp :=
  (steps clampApp tcfg rs (clickAt rs r)).1
def c0 : Runtime.State Clamp := start clampApp tcfg ⟨480, 600⟩
def c1 : Runtime.State Clamp := clampClick c0 btnA
#guard offOf c0 == 0 && topIn c0 1 == some 0
-- The new row came into view and loaded more: the list is long enough again, so row 1 is back
-- at the top of the box, and the new row just above it.
#guard c1.app.loaded && c1.app.keys.size == 7
#guard offOf c1 == 30 && topIn c1 1 == some 0

-- A clamp the reader saw stays. From there (offset 30, of a limit of 110), the box grows to 200
-- in one batch: the offset clamps to 10, and row 1 shows 20 points down. When the box shrinks
-- again, in the next batch, row 1 stays 20 points down, where the reader last saw it: the
-- offset doesn't go back to 30.
def c2 : Runtime.State Clamp := clampClick c1 btnB
#guard c2.app.tall && offOf c2 == 10 && topIn c2 1 == some 20
def c3 : Runtime.State Clamp := clampClick c2 btnB
#guard !c3.app.tall && offOf c3 == 10 && topIn c3 1 == some 20

end VListRegressions
-- endregion: fixture-vlist-settle-tests

-- region: fixture-like-tests
/-! The likes on their own (Fixture/Like.lean), replies fed by hand: request ids from 0. -/
section Likes
open Like
def l0 : Likes := {}
/-- Press post 1: it shows liked at once, and one write (request 0) goes out. -/
def p1 : Out := Like.press 1 l0 0
#guard p1.1.shown 1 && p1.1.busy 1 && p1.2.1 == 1
-- A second press while the write is in flight shows unliked and sends nothing.
#guard ((Like.press 1 p1.1 p1.2.1).1.shown 1, (Like.press 1 p1.1 p1.2.1).2.2.length) == (false, 0)
-- Refused (429): back to unliked in that step, with a line saying so.
def refused : Out := Like.receive false p1.1 1 (.reply 0 (.http 429 [] .empty))
#guard !refused.1.shown 1 && refused.1.table.settled 1
#guard refused.1.line == some "Couldn't like post 1: the server said 429"
-- Lost (a timeout): still shown liked, in doubt, and a read back (request 1) goes out.
def lost : Out := Like.receive false p1.1 1 (.reply 0 (.failed .timeout "t"))
#guard lost.1.shown 1 && lost.1.table.inDoubt 1 && lost.2.1 == 2
-- The read finds the write applied: settled, liked. Finds it not: rolled back, said.
#guard (Like.receive false lost.1 2 (.reply 1 (.http 200 [] (bit true)))).1 |> fun (l : Likes) =>
  l.shown 1 && l.table.settled 1 && l.line == none
#guard (Like.receive false lost.1 2 (.reply 1 (.http 200 [] (bit false)))).1 |> fun (l : Likes) =>
  !l.shown 1 && l.line == some "Couldn't like post 1: it never reached the server"
-- The mutant takes the lost write for a refusal and rolls back at once.
#guard !(Like.receive true p1.1 1 (.reply 0 (.failed .timeout "t"))).1.shown 1
-- A view: post 2 has 17 likes, not the viewer's. Liking it shows 18 at once.
def viewedL : Out := Like.receive false (Like.refresh l0 0).1 4 (.reply 1 (.http 200 [] (viewBody 17 false)))
#guard viewedL.1.countOf 2 == 17 && (Like.press 2 viewedL.1 4).1.countOf 2 == 18
-- A view never moves a post pressed this session.
#guard (Like.receive false (Like.refresh p1.1 1).1 5 (.reply 1 (.http 200 [] (viewBody 3 false)))).1.shown 1
end Likes
-- endregion: fixture-like-tests

end Fixture.Tests
