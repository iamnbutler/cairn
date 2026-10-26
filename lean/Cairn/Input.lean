module

public import Cairn.Geometry
public import Cairn.Claim
public import Cairn.Effects

/-! What the host sends Lean (`Event`), what the runtime gives an app (`Action`), and what an
app asks the host to do (`Effect`). -/

@[expose] public section


namespace Cairn

structure Mods where
  shift : Bool := false
  command : Bool := false
  option : Bool := false
  control : Bool := false
deriving Repr, BEq, DecidableEq, Inhabited

inductive Button where
  | primary | secondary
deriving Repr, BEq, DecidableEq, Inhabited

/-- Keys the host reports by meaning. Printable text arrives as `insertText`, not as keys;
`char` is only for shortcuts with a modifier. -/
inductive Key where
  | enter | escape | tab | backspace | delete
  | left | right | up | down | home | finish | pageUp | pageDown
  | char (c : Char)
deriving Repr, BEq, DecidableEq, Inhabited

/-- Host → Lean. Points are logical, in the window's content area. -/
inductive Event where
  | pointerMove (p : Point)
  | pointerDown (p : Point) (button : Button) (clicks : Nat) (mods : Mods)
  | pointerUp (p : Point) (button : Button) (mods : Mods)
  | pointerExit
  | scroll (p : Point) (dx dy : Int)
  | key (k : Key) (mods : Mods)
  /-- Committed text from the input system (typing, IME commit, dictation). With `replace`,
  the text replaces that range `[a, b)` of the focused field (scalar indices) instead of the
  selection. -/
  | insertText (s : String) (replace : Option (Nat × Nat) := none)
  /-- IME composition: the marked text and the selection within it, optionally replacing the
  range `replace` of the focused field. -/
  | setMarked (s : String) (selStart selLen : Nat) (replace : Option (Nat × Nat) := none)
  | unmark
  | copy | cut | selectAll | undo | redo
  | paste (s : String)
  | resize (size : Size)
  /-- Backing scale × 100 (200 on a Retina display). -/
  | scale (percent : Nat)
  | windowFocus (focused : Bool)
  /-- The host's time. The host sends one first in every batch, and before any later event
  that arrived a millisecond or more later (docs/effects.md). -/
  | clock (t : Time)
  /-- The host's answer to request `id`. -/
  | reply (id : Nat) (r : Reply)
  /-- An event from the subscription the runtime started as `id`. -/
  | subEvent (id : Nat) (e : SubEvent)
  /-- A surface-local event (pointer, key, text, resize, scale, focus) for the surface whose
  place claim is `place` (docs/surfaces.md). A bare local event is the window's, as in M1. -/
  | surface (place : ClaimId) (e : Event)
  /-- The status item `place`'s menu is opening (`menuWillOpen`). -/
  | menuOpen (place : ClaimId)
  /-- The status item `place`'s menu closed (`menuDidClose`). -/
  | menuClose (place : ClaimId)
  /-- The person chose the item `ref` in the status item `place`'s menu. -/
  | menuSelect (place : ClaimId) (ref : ControlRef)
  /-- The runtime's own, never the host's (it has no encoding): the end of a batch, before the
  frame is drawn. `Runtime.steps` runs it after every batch; it compares what is on screen with
  the last frame and delivers `Action.appear` (docs/runtime.md, "Appear"). -/
  | frame
deriving Repr, BEq, Inhabited

/-- The events from the world (`clock`, `reply`, `subEvent`); every other event is input. -/
def Event.isWorld : Event → Bool
  | .clock _ | .reply .. | .subEvent .. => true
  | _ => false

/-- The menu events (`menuOpen`, `menuClose`, `menuSelect`): about a status item's menu, not a
laid tree. -/
def Event.isMenu : Event → Bool
  | .menuOpen _ | .menuClose _ | .menuSelect .. => true
  | _ => false

def Event.isSurface : Event → Bool
  | .surface .. => true
  | _ => false

/-- Surface-local events: input a Metal surface receives (pointer, keys, text, editing, size,
scale, focus). Only these may be addressed to a surface with `Event.surface`. -/
def Event.isLocal : Event → Bool
  | .clock _ | .reply .. | .subEvent .. | .surface .. | .menuOpen _ | .menuClose _
  | .menuSelect .. | .frame => false
  | _ => true

/-- Edits to a text field's model. The runtime turns key and text events into these; the
semantics are `Cairn.Text.Field.apply`. -/
inductive TextOp where
  | insert (s : String)
  | deleteBackward | deleteForward | deleteWordBackward | deleteWordForward
  | moveLeft (extend : Bool) | moveRight (extend : Bool)
  | moveWordLeft (extend : Bool) | moveWordRight (extend : Bool)
  | moveHome (extend : Bool) | moveEnd (extend : Bool)
  | setCaret (i : Nat) (extend : Bool)
  | selectAll
  | setMarked (s : String) (selStart selLen : Nat)
  | unmark
  | cut | copy | paste (s : String)
  | undo | redo
deriving Repr, BEq, Inhabited

-- region: input-action
/-- Runtime → app. Every action names the control it came from, so every behaviour can be
traced to a claim. -/
inductive Action where
  | press (c : ControlRef)
  | doublePress (c : ControlRef)
  | edit (c : ControlRef) (op : TextOp)
  | submit (c : ControlRef)
  | cancel (c : ControlRef)
  | blur (c : ControlRef)
  /-- The control `c`, marked `Control.appear`, came on screen: at the end of a batch it has a
  visible part, and at the end of the last batch it had none or wasn't there. The runtime's, not
  a person's: no pointer or key makes it directly (docs/runtime.md, "Appear"). -/
  | appear (c : ControlRef)
deriving Repr, BEq, Inhabited
-- endregion: input-action

def Action.control : Action → ControlRef
  | .press c | .doublePress c | .edit c _ | .submit c | .cancel c | .blur c | .appear c => c

inductive Cursor where
  | arrow | pointer | text
deriving Repr, BEq, DecidableEq, Inhabited

/-- Where `Effect.scrollTo` moves a scroll box or a virtual list (docs/runtime.md, "Scrolling"). -/
inductive ScrollTarget where
  /-- Offset 0: the content's start. -/
  | start
  /-- The furthest the offset goes: the content's end at the box's end. -/
  | finish
  /-- A virtual list's row with key `k` at the top of the box. Nothing on a plain scroll box, or
  for a key the list doesn't have. -/
  | key (k : Nat)
deriving Repr, BEq, DecidableEq, Inhabited

/-- How urgently assistive apps should say an announcement (`Effect.announce`): `low` waits for
what is being spoken; `high` interrupts it. -/
inductive Priority where
  | low | high
deriving Repr, BEq, DecidableEq, Inhabited

-- region: input-effect
/-- App → host (and runtime). -/
inductive Effect where
  | setClipboard (s : String)
  | beep
  /-- Move keyboard focus to the control `c`. The runtime runs this one, not the host: after the
  step's actions it sets `ui.focus := some c`, and keeps it only if `c` is a focusable control
  of the new tree (docs/runtime.md). No `blur` is delivered for a field it takes focus from.
  The host decodes it and does nothing. -/
  | focus (c : ControlRef)
  /-- Start (or restart) the timer `name`, due `ms` milliseconds from now. The runtime keeps
  timers; the host only wakes it (docs/effects.md). -/
  | setTimer (name : String) (ms : Nat)
  /-- Forget the timer `name`; nothing if it isn't set. -/
  | cancelTimer (name : String)
  /-- Ask the host to do `r`; it answers with `Msg.reply id _`, exactly once. At most
  `App.maxInFlight` requests of capped kinds (`Request.Kind.capped`) are with the host at a time;
  the runtime holds the rest and sends them, oldest first, as slots free. -/
  | request (id : Nat) (r : Request)
  /-- Withdraw request `id` (docs/effects.md, "Requests in flight"). Its reply never reaches the
  app. A request still waiting for a slot is dropped and never sent; one already sent is cancelled
  on the host (`URLSessionTask.cancel`), and its id stays taken until the host's one reply to it
  arrives, which the runtime swallows. Nothing if `id` is not pending. -/
  | cancelRequest (id : Nat)
  /-- End the app. The host terminates after running the frame's other effects. -/
  | quit
  /-- Move the scroll box or virtual list `box` (its `Style.scrollRef`) to `to`, clamped as every
  offset is. The runtime runs this one, like `focus`: after the step's deliveries and layout it
  sets the offset against the tree just laid and lays out again (docs/runtime.md, "Scrolling").
  A box not on screen is left alone. The host decodes it and does nothing. -/
  | scrollTo (box : ControlRef) (to : ScrollTarget)
  /-- Set the Dock tile's badge to `label`; `none` clears it (docs/effects.md, "The Dock badge
  and announcements"). The host shows exactly the label; Lean decides what it says. -/
  | badge (label : Option String)
  /-- Ask assistive apps (VoiceOver) to speak `text`, for news that has no focus of its own
  ("Couldn't like the post; it's back as it was"). Posted once, with exactly this text. -/
  | announce (text : String) (priority : Priority)
deriving Repr, BEq, Inhabited
-- endregion: input-effect

end Cairn
