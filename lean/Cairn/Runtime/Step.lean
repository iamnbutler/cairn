module

public import Cairn.App
public import Cairn.Runtime.Hit
public import Cairn.Layout.Core
public import Cairn.Runtime.World

/-! The interaction runtime: turns host events into the `Action`s an app's `update` sees.

`step` is two halves. `route` reads the event against the laid tree on screen and produces
the new interaction state and a list of actions, each naming a control of that tree. `step`
then hands the actions to `app.update` in order, re-runs `view` and layout, and repairs focus,
hover and press against the new tree. The semantics are written out in docs/runtime.md. -/

@[expose] public section

namespace Cairn.Runtime

/-- What the runtime needs besides the app: text metrics and the layout function. Layout is a
parameter so the runtime and its theorems don't depend on one implementation. -/
structure Config where
  metrics : TextMetrics := TextMetrics.mono
  layout : TextMetrics → Size → Node → Laid := Cairn.Layout.layout
  /-- A panel's height for its content at a width: the content's own (hug) height. -/
  panelHeight : TextMetrics → Int → Node → Int := fun m _ n => (Cairn.Layout.measure m n).size.h

/-- What one surface shows now (docs/surfaces.md). The window's content is the state's `ui` and
`laid`; a panel's is laid out here at its width and its own height; a status item's is its
description, which `menuSelect` is checked against. -/
inductive Shown where
  | window (place : ClaimId) (title : String)
  /-- A shown panel: its view, its size (its width, its content's height) and its layout. -/
  | panel (place : ClaimId) (shown : Option (PanelView × Size × Laid))
  | status (place : ClaimId) (item : Option StatusItem)
deriving Inhabited

namespace Shown

def place : Shown → ClaimId
  | .window p _ | .panel p _ | .status p _ => p

/-- The first window's place: where bare local events go. -/
def windowPlace : List Shown → Option ClaimId
  | [] => none
  | .window p _ :: _ => some p
  | _ :: xs => windowPlace xs

/-- What status item `p` shows, if it is shown. -/
def statusOf (p : ClaimId) : List Shown → Option StatusItem
  | [] => none
  | .status q it :: xs => if q = p then it else statusOf p xs
  | _ :: xs => statusOf p xs

end Shown

structure State (S : Type) where
  app : S
  /-- Window size, hover, pressed control, focus, window focus. `view` reads this. -/
  ui : UI := {}
  /-- Click count of the pointerDown that started the current press. -/
  clicks : Nat := 0
  /-- Last pointer position in the window, `none` after it leaves. Hover follows it. -/
  pointer : Option Point := none
  /-- Backing scale × 100. -/
  scale : Nat := 100
  /-- The laid tree on screen: what the person sees and what hit testing reads. -/
  laid : Laid
  /-- Effects produced by the most recent `stepBytes` batch; the frame carries them. -/
  effects : Array Effect := #[]
  /-- The clock, timers, pending requests and subscriptions (docs/effects.md). -/
  world : World := {}
  /-- Subscription commands of the most recent `stepBytes` batch; the frame carries them. -/
  subCmds : Array SubCmd := #[]
  /-- What each of the app's surfaces shows, in the app's order. -/
  surfaces : List Shown := []

/-! ## Fields -/

/-- A field's font, view and text origin. -/
def fieldInfo (t : Target) : Option (TextStyle × FieldView × Point) :=
  match t.node with
  | .field _ _ _ ts _ v o _ _ => some (ts, v, o)
  | _ => none

/-- The index of the offset nearest `x`; the earlier one on a tie. -/
def nearest (offs : List Int) (x : Int) : Nat :=
  (go offs 0 none).getD 0
where
  go : List Int → Nat → Option (Nat × Nat) → Option Nat
    | [], _, best => best.map (·.1)
    | o :: os, i, best =>
      let d := (o - x).natAbs
      match best with
      | some (_, bd) => if d < bd then go os (i + 1) (some (i, d)) else go os (i + 1) best
      | none => go os (i + 1) (some (i, d))

/-- The caret boundary a click at `p` lands on: the nearest entry of the field's caret offsets,
measured from its `textOrigin`. -/
def caretAt (m : TextMetrics) (t : Target) (p : Point) : Nat :=
  match fieldInfo t with
  | some (ts, v, o) => nearest (m.offsets ts.font v.text).toList (p.x - o.x)
  | none => 0

def fieldLength (t : Target) : Nat :=
  match fieldInfo t with
  | some (_, v, _) => v.text.length
  | none => 0

/-- Editing keys on a focused field. Single-line fields: up and page up go home, down and
page down go to the end. -/
def editOps (k : Key) (mods : Mods) : List TextOp :=
  let sh := mods.shift
  match k with
  | .backspace =>
    if mods.command then [.moveHome true, .deleteBackward]
    else if mods.option then [.deleteWordBackward] else [.deleteBackward]
  | .delete =>
    if mods.command then [.moveEnd true, .deleteForward]
    else if mods.option then [.deleteWordForward] else [.deleteForward]
  | .left =>
    if mods.command then [.moveHome sh]
    else if mods.option then [.moveWordLeft sh] else [.moveLeft sh]
  | .right =>
    if mods.command then [.moveEnd sh]
    else if mods.option then [.moveWordRight sh] else [.moveRight sh]
  | .up | .home | .pageUp => [.moveHome sh]
  | .down | .finish | .pageDown => [.moveEnd sh]
  | _ => []

/-- Select `[a, b)` (clamped to the text) before an insert or composition that replaces it. -/
def replaceOps (t : Target) : Option (Nat × Nat) → List TextOp
  | none => []
  | some (a, b) => [.setCaret (min a (fieldLength t)) false, .setCaret (min b (fieldLength t)) true]

/-! ## Routing -/

variable {S : Type}

/-- The focused control, looked up in the tree on screen. -/
def focused (s : State S) : Option Target := s.ui.focus.bind (find s.laid)

/-- Leaving a focused field for `next` blurs it. -/
def leave (s : State S) (next : Option ControlRef) : List Action :=
  match focused s with
  | some f => if f.isField && decide (next ≠ some f.ref) then [.blur f.ref] else []
  | none => []

/-- Edits to the focused field, if a field is focused. -/
def onField (s : State S) (ops : Target → List TextOp) : List Action :=
  match focused s with
  | some t => if t.isField then (ops t).map (.edit t.ref) else []
  | none => []

def keyActions (s : State S) (k : Key) (mods : Mods) : List Action :=
  match focused s with
  | none => []
  | some t =>
    if t.isField then
      match k with
      | .enter => [.submit t.ref]
      | .escape => [.cancel t.ref]
      | _ => (editOps k mods).map (.edit t.ref)
    else
      match k with
      | .enter | .char ' ' => [.press t.ref]
      | _ => []

def textActions (s : State S) (str : String) (rep : Option (Nat × Nat)) : List Action :=
  match focused s with
  | none => []
  | some t =>
    if t.isField then (replaceOps t rep ++ [TextOp.insert str]).map (.edit t.ref)
    else if str = " " then [.press t.ref] else []

/-- Focusable controls in paint order. -/
def tabOrder (laid : Laid) : List Target := (targets laid).filter (·.focusable)

/-- The next focusable control after the focused one (or before it, going back), wrapping;
the first (or last) when nothing is focused. -/
def tabTarget (s : State S) (back : Bool) : Option Target :=
  let order := tabOrder s.laid
  match s.ui.focus.bind fun r => order.findIdx? (fun t => decide (t.ref = r)) with
  | none => if back then order.getLast? else order.head?
  | some i => order[(if back then i + order.length - 1 else i + 1) % order.length]?

def tab (s : State S) (back : Bool) : State S × List Action :=
  match tabTarget s back with
  | none => (s, [])
  | some t =>
    ({ s with ui := { s.ui with focus := some t.ref } },
     leave s (some t.ref) ++ (if t.isField then [.edit t.ref .selectAll] else []))

def withPointer (s : State S) (p : Point) : State S :=
  { s with pointer := some p, ui := { s.ui with hover := hitRef s.laid p } }

/-- Read one event against the tree on screen. Returns the new interaction state (`app` and
`laid` untouched) and the actions to deliver, in order. -/
def route (m : TextMetrics) (s : State S) : Event → State S × List Action
  | .pointerMove p =>
    (withPointer s p,
     match s.ui.pressed.bind (find s.laid) with
     | some t =>
       if t.isField && decide (s.ui.focus = some t.ref) then
         [.edit t.ref (.setCaret (caretAt m t p) true)]
       else []
     | none => [])
  | .pointerDown p .primary clicks mods =>
    let s' := { withPointer s p with clicks }
    match hitTarget s.laid p with
    | some t =>
      if t.isField then
        ({ s' with ui := { s'.ui with pressed := some t.ref, focus := some t.ref } },
         leave s (some t.ref) ++ [.edit t.ref (.setCaret (caretAt m t p) mods.shift)])
      else
        ({ s' with ui := { s'.ui with pressed := some t.ref, focus := none } }, leave s none)
    | none => ({ s' with ui := { s'.ui with pressed := none, focus := none } }, leave s none)
  | .pointerDown p .secondary _ _ => (withPointer s p, [])
  | .pointerUp p .primary _ =>
    let s' := withPointer s p
    let s' := { s' with ui := { s'.ui with pressed := none } }
    match s.ui.pressed, hitTarget s.laid p with
    | some r, some t =>
      if decide (t.ref = r) && !t.isField then
        (s', [if s.clicks = 2 then .doublePress t.ref else .press t.ref])
      else (s', [])
    | _, _ => (s', [])
  | .pointerUp p .secondary _ => (withPointer s p, [])
  | .pointerExit => ({ s with pointer := none, ui := { s.ui with hover := none } }, [])
  | .scroll .. => (s, [])
  | .key .tab mods => tab s mods.shift
  | .key k mods => (s, keyActions s k mods)
  | .insertText str rep => (s, textActions s str rep)
  | .setMarked str a b rep => (s, onField s fun t => replaceOps t rep ++ [TextOp.setMarked str a b])
  | .unmark => (s, onField s fun _ => [.unmark])
  | .copy => (s, onField s fun _ => [.copy])
  | .cut => (s, onField s fun _ => [.cut])
  | .selectAll => (s, onField s fun _ => [.selectAll])
  | .undo => (s, onField s fun _ => [.undo])
  | .redo => (s, onField s fun _ => [.redo])
  | .paste str => (s, onField s fun _ => [.paste str])
  | .resize size => ({ s with ui := { s.ui with size } }, [])
  | .scale percent => ({ s with scale := percent }, [])
  | .windowFocus b =>
    ({ s with ui := { s.ui with windowFocused := b, pressed := if b then s.ui.pressed else none } },
     [])
  | .clock _ | .reply .. | .subEvent .. => (s, [])
  | .surface p e =>
    if Shown.windowPlace s.surfaces = some p && e.isLocal then route m s e else (s, [])
  | .menuOpen p =>
    (s, match Shown.statusOf p s.surfaces with
        | some it => [.press it.control]
        | none => [])
  | .menuClose _ => (s, [])
  | .menuSelect p r =>
    (s, match Shown.statusOf p s.surfaces with
        | some it => if r ∈ MenuItem.enabledRefs it.menu then [.press r] else []
        | none => [])

/-! ## Committing -/

/-- Structural equality on `UI`, decided field by field (the derived `BEq` isn't lawful). -/
def UI.same (a b : UI) : Bool :=
  decide (a.size = b.size) && decide (a.hover = b.hover) && decide (a.pressed = b.pressed) &&
    decide (a.focus = b.focus) && decide (a.windowFocused = b.windowFocused)

theorem UI.same_eq {a b : UI} (h : UI.same a b = true) : a = b := by
  cases a; cases b
  simp only [UI.same, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩ := h
  subst h1 h2 h3 h4 h5; rfl

def relayout (app : App S) (cfg : Config) (st : S) (ui : UI) : Laid :=
  cfg.layout cfg.metrics ui.size (app.view st ui)

/-- Repair interaction state against a new tree: hover is what the pointer is over, and focus
and press survive only if their control does. -/
def fixUI (laid : Laid) (pointer : Option Point) (ui : UI) : UI :=
  { ui with
    hover := pointer.bind (hitRef laid)
    focus := ui.focus.filter (focusableIn laid)
    pressed := ui.pressed.filter (present laid) }

/-- View and lay out, repair `ui0` against the result, and repeat while the repair changes
what the view saw (hover reveals, focus rings), up to `fuel` more times. The result is always
`ui0` repaired against the tree returned with it. -/
def settle (app : App S) (cfg : Config) (st : S) (pointer : Option Point) (ui0 : UI) :
    Nat → UI → UI × Laid
  | fuel, ui =>
    let l := relayout app cfg st ui
    let ui' := fixUI l pointer ui0
    match fuel with
    | 0 => (ui', l)
    | f + 1 => if UI.same ui' ui then (ui', l) else settle app cfg st pointer ui0 f ui'

/-- How many times `settle` may re-run the view after the first layout. -/
def settleFuel : Nat := 2

/-- A shown panel's size: its width and its content's height at that width. -/
def panelSize (cfg : Config) (v : PanelView) : Size :=
  let w : Int := v.width
  ⟨w, max 0 (cfg.panelHeight cfg.metrics w v.content)⟩

/-- Lay out a shown panel at its size. -/
def layPanel (cfg : Config) (v : PanelView) : Size × Laid :=
  let sz := panelSize cfg v
  (sz, cfg.layout cfg.metrics sz v.content)

/-- What one surface shows in app state `st`. -/
def Surface.show (cfg : Config) (st : S) : Surface S → Shown
  | .window p t _ => .window p t
  | .panel p v => .panel p ((v st).map fun pv => (pv, layPanel cfg pv))
  | .statusItem p v => .status p (v st)

/-- What every surface shows in app state `st`. -/
def shows (app : App S) (cfg : Config) (st : S) : List Shown :=
  app.surfaces.map (Surface.show cfg st)

/-- Run `update` over the actions in order, collecting effects. -/
def deliver (update : S → Action → S × List Effect) (st : S) (acts : List Action) :
    S × List Effect :=
  acts.foldl (fun (st, effs) a => let (st', e) := update st a; (st', effs ++ e)) (st, [])

/-- The focus the effects ask for: the last `Effect.focus`, if any. -/
def requestedFocus (effs : List Effect) : Option ControlRef :=
  effs.foldl (fun acc e => match e with | .focus c => some c | _ => acc) none

/-- Run the focus requests in `effs` on a `UI`. `settle` then keeps the focus only if its
control is focusable in the new tree. -/
def applyFocus (effs : List Effect) (ui : UI) : UI :=
  match requestedFocus effs with
  | some c => { ui with focus := some c }
  | none => ui

/-! ## The outside world (docs/effects.md) -/

/-- An event's progress through the app: its state, the world, the effects that go on the
frame, and whether anything was delivered. -/
structure Ctx (S : Type) where
  app : S
  world : World
  effs : List Effect := []
  delivered : Bool := false

/-- Deliver a message to `receive` and take in its effects. -/
def give (app : App S) (c : Ctx S) (m : Msg) : Ctx S :=
  let (st, es) := app.receive c.app m
  let (w, kept) := c.world.absorb es
  { app := st, world := w, effs := c.effs ++ kept, delivered := true }

/-- Tell the app the time, if it hasn't heard the current one. -/
def hear (app : App S) (c : Ctx S) : Ctx S :=
  if c.world.heard = some c.world.clock then c
  else give app { c with world := { c.world with heard := some c.world.clock } } (.clock c.world.clock)

/-- Fire `n` if it is still set and due: it leaves the table, then is delivered. -/
def fire (app : App S) (c : Ctx S) (n : String) : Ctx S :=
  if c.world.dueNow n then give app { c with world := c.world.cancelTimer n } (.timer n) else c

/-- On the first clock: the app hears the time, then `initEffects` run. -/
def boot (app : App S) (c : Ctx S) : Ctx S :=
  if c.world.booted then c else
  let c := hear app { c with world := { c.world with booted := true } }
  let (w, kept) := c.world.absorb app.initEffects
  { c with world := w, effs := c.effs ++ kept, delivered := true }

/-- What the world events deliver: a clock event fires due timers, a reply is delivered if its
id is pending and it answers that kind, and a subscription event if its id is active. Other
events deliver nothing here (their actions come from `route`). -/
def admit (app : App S) (s : State S) : Event → Ctx S
  | .clock t =>
    let c := boot app { app := s.app, world := s.world.tick t }
    let due := c.world.dueNames
    if due.isEmpty then c else due.foldl (fire app) (hear app c)
  | .reply id r =>
    -- The time first, then the reply leaves the pending table: what `receive` makes of the
    -- clock sees the request still pending.
    if (s.world.takeReply id r).isSome then
      let c := hear app { app := s.app, world := s.world }
      match c.world.takeReply id r with
      | some w => give app { c with world := w } (.reply id r)
      | none => c
    else { app := s.app, world := s.world }
  | .subEvent id e =>
    match s.world.subOf id with
    | some sub => give app (hear app { app := s.app, world := s.world }) (.sub sub e)
    | none => { app := s.app, world := s.world }
  | _ => { app := s.app, world := s.world }

/-- Deliver the routed actions to `update` (after the time, if the app hasn't heard it) and take
in their effects, in order. -/
def act (app : App S) (c : Ctx S) (acts : List Action) : Ctx S :=
  if acts.isEmpty then c else
  let c := hear app c
  let (st, es) := deliver app.update c.app acts
  let (w, kept) := c.world.absorb es
  { app := st, world := w, effs := c.effs ++ kept, delivered := true }

/-- One event. -/
def step (app : App S) (cfg : Config) (s : State S) (e : Event) : State S × List Effect :=
  let (s1, acts) := route cfg.metrics s e
  let c0 := admit app s e
  if acts.isEmpty && !c0.delivered && UI.same s1.ui s.ui then ({ s1 with world := c0.world }, c0.effs)
  else
  let c := act app c0 acts
  let (subs, cmds, next) :=
    if c.delivered then diffSubs c.world.subs (app.subscriptions c.app) c.world.nextSub
    else (c.world.subs, [], c.world.nextSub)
  let ui1 := applyFocus c.effs s1.ui
  let (ui, laid) := settle app cfg c.app s1.pointer ui1 settleFuel ui1
  let surfaces := if c.delivered then shows app cfg c.app else s1.surfaces
  ({ s1 with app := c.app, ui, laid, world := { c.world with subs, nextSub := next },
             subCmds := s1.subCmds ++ cmds.toArray, surfaces }, c.effs)

/-- A batch of events, in order. -/
def steps (app : App S) (cfg : Config) (s : State S) (es : List Event) : State S × List Effect :=
  es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e')) (s, [])

/-- The first state: the app's `init` at a window size, laid out, with the app's `initFocus`
if that control is focusable. -/
def start (app : App S) (cfg : Config) (size : Size) (scale : Nat := 100) : State S :=
  let ui0 : UI := { size, focus := app.initFocus }
  let (ui, laid) := settle app cfg app.init none ui0 settleFuel ui0
  { app := app.init, ui, laid, scale, surfaces := shows app cfg app.init }

/-- The cursor the host shows: text over fields, a pointing hand over other controls. -/
def cursor (s : State S) : Cursor :=
  match s.ui.hover.bind (find s.laid) with
  | some t => if t.isField then .text else .pointer
  | none => .arrow

end Cairn.Runtime
