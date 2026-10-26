import Cairn.Fuzz.Target
import Cairn.Fuzz.Text
import Cairn.Fuzz.Metrics
import Cairn.Fuzz.Host
import Cairn.Runtime
import Cairn.Layout.Check
import Cairn.Frame.Dump
import Std.Data.HashMap
import Std.Data.HashSet

/-! # The walk

One sequence: a window size, text metrics, and operations generated from the current state
(or replayed from a list), each checked against the app's claims (docs/fuzz.md).

An app with an `App` is driven through the real runtime (`Runtime.route` and `Runtime.step`):
an action is performed as the pointer and key events a person would use, so hit testing, focus
and routing are exercised along with the app. A machine without an `App` gets its actions
directly (`machine.update`).

Between a person's operations the host has its say (`Cairn.Fuzz.Host`): it answers the requests
the frames carried, fires timers by sending the clock, sends subscription events and drops
images, as the trusted claims allow. -/

namespace Cairn.Fuzz
open Cairn Cairn.Claims Cairn.Runtime Cairn.Layout

/-- One operation of a sequence. Self-contained, so a subsequence replays without the seed. -/
inductive Op where
  /-- An action of a move, performed through the UI (or delivered, without an `App`). -/
  | act (a : Action)
  | click (p : Point) (clicks : Nat)
  | move (p : Point)
  /-- A wheel or trackpad scroll at `p`, in points (positive toward the end, trusted ^1012). -/
  | scroll (p : Point) (dx dy : Int)
  | tab (back : Bool)
  | key (k : Key) (mods : Mods)
  | resize (size : Size)
  | exit
  | windowFocus (b : Bool)
  /-- The host's move: a reply, the clock, a subscription event, an eviction. -/
  | host (h : HostOp)
deriving Repr, BEq, Inhabited

/-! ### As text: flow witness syntax for actions -/

def refLean (c : ControlRef) : String :=
  if c.key = 0 then s!"^{c.claim}" else s!"^{c.claim}#{c.key}"

def opLean : TextOp → String
  | .insert s => s!"(.insert {s.quote})"
  | .deleteBackward => "(.deleteBackward)"
  | .deleteForward => "(.deleteForward)"
  | .deleteWordBackward => "(.deleteWordBackward)"
  | .deleteWordForward => "(.deleteWordForward)"
  | .moveLeft e => s!"(.moveLeft {e})"
  | .moveRight e => s!"(.moveRight {e})"
  | .moveWordLeft e => s!"(.moveWordLeft {e})"
  | .moveWordRight e => s!"(.moveWordRight {e})"
  | .moveHome e => s!"(.moveHome {e})"
  | .moveEnd e => s!"(.moveEnd {e})"
  | .setCaret i e => s!"(.setCaret {i} {e})"
  | .selectAll => "(.selectAll)"
  | .setMarked s a b => s!"(.setMarked {s.quote} {a} {b})"
  | .unmark => "(.unmark)"
  | .cut => "(.cut)"
  | .copy => "(.copy)"
  | .paste s => s!"(.paste {s.quote})"
  | .undo => "(.undo)"
  | .redo => "(.redo)"

def actionLean : Action → String
  | .press c => s!"press {refLean c}"
  | .doublePress c => s!"doublePress {refLean c}"
  | .edit c op => s!"edit {refLean c} {opLean op}"
  | .submit c => s!"submit {refLean c}"
  | .cancel c => s!"cancel {refLean c}"
  | .blur c => s!"blur {refLean c}"
  | .appear c => s!"appear {refLean c}"

def keyText (k : Key) (m : Mods) : String :=
  let name := match k with
    | .enter => "Enter" | .escape => "Escape" | .tab => "Tab" | .backspace => "Backspace"
    | .delete => "Delete" | .left => "Left" | .right => "Right" | .up => "Up" | .down => "Down"
    | .home => "Home" | .finish => "End" | .pageUp => "PageUp" | .pageDown => "PageDown"
    | .char c => c.toString
  (if m.command then "cmd-" else "") ++ (if m.option then "opt-" else "") ++
    (if m.shift then "shift-" else "") ++ name

/-- An operation, as a person would say it. -/
def opText : Op → String
  | .act a => actionLean a
  | .click p n => s!"{if n ≥ 2 then "double-click" else "click"} at ({p.x}, {p.y})"
  | .move p => s!"pointer to ({p.x}, {p.y})"
  | .scroll p dx dy => s!"scroll ({dx}, {dy}) at ({p.x}, {p.y})"
  | .tab back => if back then "key shift-Tab" else "key Tab"
  | .key k m => s!"key {keyText k m}"
  | .resize z => s!"resize to {z.w}×{z.h}"
  | .exit => "pointer leaves the window"
  | .windowFocus b => if b then "window gains focus" else "window loses focus"
  | .host h => h.text


/-! ### Secure fields: printed as their length

What a person typed into a secure field (`FieldView.secure`) is printed as bullets, one per
scalar, in every report, shrunk sequence, flow and failure message: a fuzz report never holds
it (docs/fuzz.md, "Secure fields"). -/

/-- The secure fields in a laid tree. -/
def secureRefs (l : Laid) : List ControlRef :=
  (targets l).filterMap fun tg => match tg.node with
    | .field _ _ _ _ c v .. => if v.secure then some c.ref else none
    | _ => none

def bulletsOf (s : String) : String := Text.bullets s.length

/-- A text operation with its text replaced by bullets. -/
def redactText : TextOp → TextOp
  | .insert s => .insert (bulletsOf s)
  | .paste s => .paste (bulletsOf s)
  | .setMarked s a b => .setMarked (bulletsOf s) a b
  | op => op

/-- An action, with an edit of one of `secure` redacted. -/
def redactAction (secure : List ControlRef) : Action → Action
  | .edit c op => .edit c (if secure.contains c then redactText op else op)
  | a => a

def Op.redactIn (secure : List ControlRef) : Op → Op
  | .act a => .act (redactAction secure a)
  | op => op

/-- A failed check: which check, on which claim and key, after which operation. -/
structure Failure where
  check : String
  claim : ClaimId
  key : Nat := 0
  step : Nat := 0
  message : String
deriving Repr, Inhabited

def mkFail (check : String) (r : ControlRef) (step : Nat) (message : String) : Failure :=
  { check, claim := r.claim, key := r.key, step, message }

def Failure.same (a b : Failure) : Bool := a.check == b.check && a.claim == b.claim

/-- A check that ran on a claim: `(claim, check kind)`. -/
abbrev Ran := ClaimId × String

/-- How a sequence starts. -/
structure Setup where
  seed : Nat
  size : Size
  metrics : MetricsChoice
  /-- The host's clock when the sequence starts: its first clock boots the app. -/
  start : Time := {}
deriving Repr, Inhabited

section
variable (t : Target)

def cfgOf (m : MetricsChoice) : Config := { metrics := m.metrics }

/-- The app, or a stand-in with an empty view for a machine without one. -/
def Target.runApp : App t.S :=
  t.app.getD { init := t.machine.init, surfaces := [],
               update := t.machine.update, claims := [] }

def Target.move? (id : ClaimId) : Option (Move t.S) := find? t.machine.moves id

def Target.isKeyed (id : ClaimId) : Bool := t.keyed.contains id

def Target.budgetNs : Nat := t.custom.budgetNs.getD 8_000_000

/-- The smallest window for a state: the fuzz config's; else the minimum the app asks the host
for (`App.minSize`), which the host keeps the window at or above (trusted ^1010), so a person
never sees a smaller one; else, when the app asks for none, the view's preferred size. -/
def Target.minSize (m : TextMetrics) (s : t.S) (ui : UI) : Size :=
  match t.custom.minSize s, t.app with
  | some z, _ => z
  | none, some app =>
    let z := app.minSize s
    if 0 < z.w || 0 < z.h then z else (measure m ui.size.w (app.view s ui)).size
  | none, none => ⟨0, 0⟩

end

/-! ## The world a sequence runs in -/

variable {S W : Type}

/-- A sequence's state: the runtime's, what the fuzzer has seen, the host's, and the world of
the app's server (`Custom.server`; `Unit` without one). -/
structure World (S W : Type) where
  rt : Runtime.State S
  /-- The largest key seen on screen per keyed move, so "enabled but missing" can be probed. -/
  seen : Std.HashMap ClaimId Nat := {}
  /-- The host: what the frames asked of it, its clock, its images. -/
  host : Host := {}
  /-- Every secure field seen on screen so far, whose edits are printed redacted. -/
  secure : List ControlRef := []
  /-- What the app's server holds. Only `perform` and `drain` change it, and they hold its only
  reference while they do. -/
  server : W
  /-- The virtual lists the app keeps (`App.keepScroll`) that are not on screen, with the row
  that was first showing when each left, and where in the box. -/
  parked : List (ControlRef × Nat × Int) := []
  /-- Each virtual list as it was last on screen: while a list is off screen (hidden, kept), none
  of its rows is laid, so a control keyed like one of its rows may be missing. -/
  lastLists : List LaidList := []

/-- The host after a step: it takes in the effects the frame carried, the frame's images count
as used, and the subscriptions the runtime stopped are remembered (their events can still be in
flight). -/
def Host.after (h : Host) (before : List (Nat × Sub)) (rt : Runtime.State S) (es : List Effect) :
    Host :=
  let h := (h.absorb es).touch (drawnBy rt)
  let now := rt.world.subs
  let gone := before.filter fun p => !(now.any (·.1 == p.1))
  let live := fun (id : Nat) => now.any (·.1 == id)
  { h with stopped := (gone ++ h.stopped).take 8, started := h.started.filter live,
           keysDown := h.keysDown.filter live }

/-- The server's world a sequence starts with: `Server.init` from the sequence's seed. -/
def serverStart (t : Target) (setup : Setup) : t.W :=
  (t.srv.init.run (Rng.ofSeed (setup.seed + 0x5e7e7))).1

/-- The first frame, then the host's first clock, which boots the app (`App.initEffects`). -/
def World.start (t : Target) (setup : Setup) : World t.S t.W :=
  let cfg := cfgOf setup.metrics
  let rt0 := Runtime.start t.runApp cfg setup.size
  let h0 : Host := { now := setup.start }
  match t.app with
  | none => { rt := rt0, host := h0, server := serverStart t setup }
  | some app =>
    let (rt, es) := step app cfg rt0 (.clock setup.start)
    let rt := { rt with subCmds := #[] }
    { rt, host := { h0 with stats := { clocks := 1 } }.after rt0.world.subs rt es,
      server := serverStart t setup }

/-- The events a text operation arrives as. `setCaret` has none (it comes from clicks). -/
def opEvents : TextOp → List Event
  | .insert s => [.insertText s]
  | .deleteBackward => [.key .backspace {}]
  | .deleteForward => [.key .delete {}]
  | .deleteWordBackward => [.key .backspace { option := true }]
  | .deleteWordForward => [.key .delete { option := true }]
  | .moveLeft e => [.key .left { shift := e }]
  | .moveRight e => [.key .right { shift := e }]
  | .moveWordLeft e => [.key .left { shift := e, option := true }]
  | .moveWordRight e => [.key .right { shift := e, option := true }]
  | .moveHome e => [.key .left { shift := e, command := true }]
  | .moveEnd e => [.key .right { shift := e, command := true }]
  | .setCaret .. => []
  | .selectAll => [.selectAll]
  | .setMarked s a b => [.setMarked s a b]
  | .unmark => [.unmark]
  | .cut => [.cut]
  | .copy => [.copy]
  | .paste s => [.paste s]
  | .undo => [.undo]
  | .redo => [.redo]

def clickEvents (p : Point) (clicks : Nat) : List Event :=
  [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}] ++
    (if clicks ≥ 2 then [.pointerDown p .primary 2 {}, .pointerUp p .primary {}] else [])

/-- The controls a shown status item puts on screen besides the window's laid tree: its button
(`StatusItem.control`, pressed by opening its menu) and its menu's items, each with its place and
whether it is enabled. The frame carries them in its surface records (docs/surfaces.md); the host
builds the button and a real `NSMenu` from them, so they are on screen whenever the item is shown,
the menu's items whether or not it is open. -/
def statusControls (rt : Runtime.State S) : List (ClaimId × ControlRef × Bool) :=
  rt.surfaces.flatMap fun
    | .status p (some it) =>
      (p, it.control, true) :: (MenuItem.refs it.menu).map fun r =>
        (p, r, (MenuItem.enabledRefs it.menu).any fun x => decide (x = r))
    | _ => []

/-- Whether `r` is an enabled control on a status item: one a person can press now. -/
def onStatus (rt : Runtime.State S) (r : ControlRef) : Bool :=
  (statusControls rt).any fun (_, x, e) => e && decide (x = r)

/-- The events that press `c` on a status item: opening the menu for its button, choosing the
item for a menu item (`Runtime.step`'s `menuOpen` and `menuSelect`). -/
def statusPress (rt : Runtime.State S) (c : ControlRef) : Option (List Event) :=
  (statusControls rt).findSome? fun (p, x, e) =>
    if !(e && decide (x = c)) then none
    else match Shown.statusOf p rt.surfaces with
      | some it => if decide (it.control = c) then some [.menuOpen p] else some [.menuSelect p c]
      | none => none

/-- The events that perform an operation in the current state; `none` when an action's control
isn't on screen (or can't take that action), so the operation is skipped. -/
def opToEvents (rt : Runtime.State S) : Op → Option (List Event)
  | .act a =>
    let c := a.control
    match find rt.laid c with
    | none =>
      match a with
      | .press _ => statusPress rt c
      | _ => none
    | some tg =>
      -- A control scrolled out of view can't be clicked: skip the operation.
      if !decide tg.visible.nonempty then none else
      let p := tg.visible.center
      let focus := if rt.ui.focus = some c then [] else clickEvents p 1
      match a with
      | .press _ => if tg.isField then none else some (clickEvents p 1)
      | .doublePress _ => if tg.isField then none else some (clickEvents p 2)
      | .edit _ op =>
        if tg.isField && !(opEvents op).isEmpty then some (focus ++ opEvents op) else none
      | .submit _ => if tg.isField then some (focus ++ [.key .enter {}]) else none
      | .cancel _ => if tg.isField then some (focus ++ [.key .escape {}]) else none
      | .blur _ => if tg.isField then some (focus ++ [.key .tab {}]) else none
      -- The runtime's, not a person's: it comes with the frame that shows the control.
      | .appear _ => none
  | .click p n => some (clickEvents p n)
  | .move p => some [.pointerMove p]
  | .scroll p dx dy => some [.pointerMove p, .scroll p dx dy]
  | .tab back => some [.key .tab { shift := back }]
  | .key k mods => some [.key k mods]
  | .resize z => some [.resize z]
  | .exit => some [.pointerExit]
  | .windowFocus b => some [.windowFocus b]
  | .host _ => none

/-- The host's events for its move, the host once it has made it, and the message it sent (for
`Custom.relations`); `none` when the move can't happen now (a replayed subsequence whose request
was never made). Every batch starts with the clock (^908). -/
def hostPlan (rt : Runtime.State S) (h : Host) : HostOp → Option (Host × List Event × Option Msg)
  | .advance ms j =>
    let now : Time := { h.now with mono := h.now.mono + ms, wall := h.now.wall + ms + j }
    some ({ h with now, stats := { h.stats with clocks := h.stats.clocks + 1 } }, [.clock now],
      some (.clock now))
  | .wake late =>
    match rt.world.wake with
    | none => none
    | some due =>
      let mono := max h.now.mono (due + late)
      let now : Time := { h.now with mono, wall := h.now.wall + (mono - h.now.mono : Nat) }
      some ({ h with now, stats := { h.stats with wakes := h.stats.wakes + 1 } }, [.clock now],
        some (.clock now))
  | .reply id r =>
    match h.request? id with
    | none => none
    | some req =>
      let wasCancelled := h.isCancelled id
      let ready := (h.ready.lookup id).isSome
      let h1 := h.answer id
      let (h2, extra) : Host × List Event := match req, r with
        | .loadImage src _, .image w ht => (if ready then h1 else h1.put src w ht, [])
        | .loadImage src true, .failed .. =>
          -- A failed reload drops what was held (^1006) and says so (^1011); a cancelled one
          -- leaves it (^1009).
          if !wasCancelled && (h1.heldOf src).isSome then (h1.drop src, notices rt src) else (h1, [])
        | _, _ => (h1, [])
      let st := h2.stats
      let st := if wasCancelled then { st with cancelledReplies := st.cancelledReplies + 1 }
        else { st with replies := st.replies + 1,
                       failed := st.failed + (if r matches .failed .. then 1 else 0) }
      some ({ h2 with stats := st }, [.clock h.now, .reply id r] ++ extra, some (.reply id r))
  | .load id w ht =>
    match h.request? id with
    | some (.loadImage src _) =>
      if h.isCancelled id || (h.ready.lookup id).isSome then none else
      let h := h.put src w ht
      some ({ h with ready := (id, .image w ht) :: h.ready,
                     stats := { h.stats with loads := h.stats.loads + 1 } }, [], none)
    | _ => none
  | .sub sub e dt =>
    match rt.world.subs.find? (·.2 == sub) with
    | none => none
    | some (id, _) =>
      let now : Time := { h.now with mono := h.now.mono + dt, wall := h.now.wall + dt }
      let h := { h with now, stats := { h.stats with subEvents := h.stats.subEvents + 1 } }
      let h := match e with
        | .started _ => { h with started := id :: h.started }
        | .keyDown _ => { h with keysDown := id :: h.keysDown }
        | .keyUp _ => { h with keysDown := h.keysDown.erase id }
        | _ => h
      some (h, [.clock now, .subEvent id e], some (.sub sub e))
  | .late id e =>
    match h.stopped.lookup id with
    | none => none
    | some sub =>
      if rt.world.subs.any (·.1 == id) then none else
      some ({ h with stats := { h.stats with lateSubEvents := h.stats.lateSubEvents + 1 } },
        [.clock h.now, .subEvent id e], some (.sub sub e))
  | .evict src =>
    if evictable h rt != some src then none else
    let b := ((imageCaches rt).head?.map (·.2)).getD 0
    some ({ (h.drop src) with stats := { h.stats with evictions := h.stats.evictions + 1 } },
      [.clock h.now] ++ notices rt src, some (.sub (.imageCache b) (.evicted src)))
  | .stray id r =>
    if h.isSent id || (rt.world.pending.lookup id).isSome || rt.world.isStopping id then none else
    some ({ h with stats := { h.stats with stray := h.stats.stray + 1 } },
      [.clock h.now, .reply id r], some (.reply id r))
  -- A server's moves (`hostStep`).
  | .serve .. | .lose .. | .fail .. | .tick _ => none

/-- The host's move with server `sv` (`Custom.server`), whose world is `sw`: the world after,
and the host, events and message as `hostPlan`'s, or `none` when the move can't happen now (then
the world is `sw`). `serve` and `tick` change the world; a `reply` to a request the server takes
sends the reply it gave (and can't happen until it has given one); `lose` (lost after) and
`fail` (failed before) answer a request it takes with a fault, after and before it handled it.
Every other move is `hostPlan`'s, and leaves the world alone. The world is returned even when
the move can't happen, so the caller never keeps a second reference to it. -/
def hostStep (sv : Server S) (rt : Runtime.State S) (h : Host) (sw : sv.W) :
    HostOp → sv.W × Option (Host × List Event × Option Msg)
  | .serve id seed =>
    match h.request? id with
    | none => (sw, none)
    | some req =>
      if !sv.takes req then (sw, none) else
      let again := (h.ready.lookup id).isSome
      let ((sw', rep), _) := (sv.handle sw id req).run (Rng.ofSeed seed)
      let rep := if rep.answers req.kind then rep
        else .failed .other "fuzz: the server answered the wrong kind"
      (sw', some ({ h with ready := (id, rep) :: h.ready.filter (·.1 != id),
                           stats := { h.stats with served := h.stats.served + 1,
                                                   retransmits := h.stats.retransmits + (if again then 1 else 0) } },
                  [], none))
  | .tick seed =>
    if sv.ticks == 0 then (sw, none) else
    (((sv.tick sw).run (Rng.ofSeed seed)).1,
     some ({ h with stats := { h.stats with ticks := h.stats.ticks + 1 } }, [], none))
  | .reply id r =>
    (sw, match h.request? id with
      | none => none
      | some req =>
        if !sv.takes req then hostPlan rt h (.reply id r)
        else match h.ready.lookup id with
          | none => none
          | some rep => hostPlan rt h (.reply id rep))
  | .lose id r =>
    (sw, match h.request? id with
      | none => none
      | some req =>
        if sv.takes req && (h.ready.lookup id).isSome then
          (hostPlan rt h (.reply id r)).map fun (h', es, m) =>
            ({ h' with stats := { h'.stats with lostAfter := h'.stats.lostAfter + 1 } }, es, m)
        else none)
  | .fail id r =>
    (sw, match h.request? id with
      | none => none
      | some req =>
        if sv.takes req && (h.ready.lookup id).isNone then
          (hostPlan rt h (.reply id r)).map fun (h', es, m) =>
            ({ h' with stats := { h'.stats with failedBefore := h'.stats.failedBefore + 1 } }, es, m)
        else none)
  | op => (sw, hostPlan rt h op)

/-! ### What the host does with a server

Two facts about `hostStep`, which hold with any server (`Server.empty` included), so with a
server present the host answers as it did without one:

- each request is answered at most once: a `reply`, a `lose` or a `fail` answers only a request
  the host holds, and the host holds it no more after (`hostStep_answers_once`), so a second
  answer to it can't happen (`hostStep_no_second_answer`). A request the app cancelled is
  answered once too (^1009), and the runtime swallows it (`step_reply_ignored`); a `stray` goes
  only to ids neither holds (`hostPlan`);
- a failed-before answer leaves the server's world as it was, as do a lost-after answer and a
  `reply` (`hostStep_fail_world`): only `serve` and `tick` change it. -/

/-- The moves that answer request `id`. -/
def HostOp.answers (id : Nat) : HostOp → Bool
  | .reply i _ | .lose i _ | .fail i _ => i == id
  | _ => false

theorem lookup_filter_ne (l : List (Nat × Request)) (id : Nat) :
    (l.filter (·.1 != id)).lookup id = none := by
  induction l with
  | nil => rfl
  | cons p ps ih =>
    obtain ⟨i, q⟩ := p
    by_cases hi : i = id
    · rw [List.filter_cons_of_neg (by simp [hi])]; exact ih
    · rw [List.filter_cons_of_pos (by simp [hi])]
      simp only [List.lookup, show (id == i) = false from by simp [Ne.symm hi]]
      exact ih

/-- A reply leaves the host holding every request but the one answered. -/
theorem hostPlan_reply_sent {rt : Runtime.State S} {h h' : Host} {id : Nat} {r : Reply}
    {es : List Event} {m : Option Msg} (hp : hostPlan rt h (.reply id r) = some (h', es, m)) :
    h'.sent = h.sent.filter (·.1 != id) := by
  simp only [hostPlan] at hp
  split at hp
  · cases hp
  · simp only [Option.some.injEq, Prod.mk.injEq] at hp
    obtain ⟨rfl, -, -⟩ := hp
    split <;> (try split) <;> rfl

/-- **Each request is answered at most once**, with or without a server: a move that answers
request `id` happens only while the host holds it, and the host holds it no more after. -/
theorem hostStep_answers_once (sv : Server S) (rt : Runtime.State S) (h : Host) (sw : sv.W)
    (op : HostOp) (id : Nat) (ha : op.answers id = true) {h' : Host} {es : List Event}
    {m : Option Msg} (hs : (hostStep sv rt h sw op).2 = some (h', es, m)) :
    (h.request? id).isSome ∧ h'.request? id = none := by
  have gone : ∀ {r : Reply} {h'' : Host} {es' : List Event} {m' : Option Msg},
      hostPlan rt h (.reply id r) = some (h'', es', m') → h''.request? id = none := by
    intro r h'' es' m' hp
    simp only [Host.request?, hostPlan_reply_sent hp, lookup_filter_ne]
  cases op with
  | reply i r =>
    simp only [HostOp.answers, beq_iff_eq] at ha; subst ha
    simp only [hostStep] at hs
    split at hs
    · cases hs
    · rename_i req hreq
      refine ⟨by simp [hreq], ?_⟩
      split at hs
      · exact gone hs
      · split at hs
        · cases hs
        · exact gone hs
  | lose i r =>
    simp only [HostOp.answers, beq_iff_eq] at ha; subst ha
    simp only [hostStep] at hs
    split at hs
    · cases hs
    · rename_i req hreq
      refine ⟨by simp [hreq], ?_⟩
      split at hs
      · obtain ⟨⟨h'', es', m'⟩, hp, he⟩ := Option.map_eq_some_iff.mp hs
        simp only [Prod.mk.injEq] at he
        obtain ⟨rfl, -, -⟩ := he
        simpa only [Host.request?] using gone hp
      · cases hs
  | fail i r =>
    simp only [HostOp.answers, beq_iff_eq] at ha; subst ha
    simp only [hostStep] at hs
    split at hs
    · cases hs
    · rename_i req hreq
      refine ⟨by simp [hreq], ?_⟩
      split at hs
      · obtain ⟨⟨h'', es', m'⟩, hp, he⟩ := Option.map_eq_some_iff.mp hs
        simp only [Prod.mk.injEq] at he
        obtain ⟨rfl, -, -⟩ := he
        simpa only [Host.request?] using gone hp
      · cases hs
  | _ => simp [HostOp.answers] at ha

/-- So no second answer: once a move has answered request `id`, no move answers it again from
the host it leaves (until a new request with that id is sent, which the runtime never does). -/
theorem hostStep_no_second_answer (sv : Server S) (rt rt' : Runtime.State S) (h : Host)
    (sw sw' : sv.W) (op op' : HostOp) (id : Nat) (ha : op.answers id = true)
    (ha' : op'.answers id = true) {h' : Host} {es : List Event} {m : Option Msg}
    (hs : (hostStep sv rt h sw op).2 = some (h', es, m)) :
    (hostStep sv rt' h' sw' op').2 = none := by
  have hn := (hostStep_answers_once sv rt h sw op id ha hs).2
  cases op' with
  | reply i r | lose i r | fail i r =>
    simp only [HostOp.answers, beq_iff_eq] at ha'; subst ha'
    simp only [hostStep, hn]
  | _ => simp [HostOp.answers] at ha'

/-- **A failed-before answer leaves the world as it was** (by construction), and so do a
lost-after answer and a reply. -/
theorem hostStep_fail_world (sv : Server S) (rt : Runtime.State S) (h : Host) (sw : sv.W)
    (id : Nat) (r : Reply) : (hostStep sv rt h sw (.fail id r)).1 = sw := rfl

theorem hostStep_lose_world (sv : Server S) (rt : Runtime.State S) (h : Host) (sw : sv.W)
    (id : Nat) (r : Reply) : (hostStep sv rt h sw (.lose id r)).1 = sw := rfl

theorem hostStep_reply_world (sv : Server S) (rt : Runtime.State S) (h : Host) (sw : sv.W)
    (id : Nat) (r : Reply) : (hostStep sv rt h sw (.reply id r)).1 = sw := rfl

/-- The result of performing one operation. -/
structure Performed (S W : Type) where
  world : World S W
  /-- The actions delivered to `update`, in order. -/
  acts : List Action
  /-- Whether the operation ran at all (an `act` whose control is missing is skipped). -/
  ran : Bool
  /-- The slowest event's `Runtime.step` (update, view, layout, settle), in nanoseconds. -/
  maxNs : Nat
  /-- A press or double press the runtime dropped by design: its pointerDown delivered a `blur`,
  and after that step the pressed control is no longer at the point, so the release lands
  elsewhere and presses nothing (docs/runtime.md; TodoMVC decision T33 in docs/plan.md: the
  edit saves first, and if saving moved what was clicked, the click is dropped). This is
  exactly where `Runtime.click_presses`'s hypothesis fails, so "performed" does not apply. -/
  dropped : Bool := false
  /-- The message the host sent, for a host's move (`Custom.relations`). -/
  msg : Option Msg := none
  /-- The effects the operation's steps put on the frame. -/
  effects : List Effect := []
  /-- Whether the runtime dropped the host's message without delivering it. -/
  msgDropped : Bool := false

/-- Perform an operation: through the runtime with an `App`, or straight into the machine.
A person's operation is one batch, stamped with the host's clock (^908); a host's move is its
own batch. The host takes in the effects of every step. -/
def perform (t : Target) (setup : Setup) (w : World t.S t.W) (op : Op) :
    IO (Performed t.S t.W) := do
  let cfg := cfgOf setup.metrics
  match t.app with
  | none =>
    match op with
    | .act a =>
      let s := w.rt.app
      let s' ← IO.lazyPure fun _ => (t.machine.update s a).1
      let acts := if accepts t.machine.moves s a then [a] else []
      return { world := { w with rt := { w.rt with app := s' } }, acts, ran := true, maxNs := 0 }
    | _ => return { world := w, acts := [], ran := false, maxNs := 0 }
  | some app =>
    -- Take the world apart first, so the server's world has one reference when `hostStep`
    -- hands it to the server (`LEAN_ABORT_ON_NONLINEAR=1`).
    let { rt := rt0, seen, host := host0, secure, server := sw0, parked, lastLists } := w
    let (sw, plan) : t.W × Option (Host × List Event × Option Msg) := match op with
      | .host h => hostStep t.srv rt0 host0 sw0 h
      | _ => (sw0, (opToEvents rt0 op).map fun es => (host0, .clock host0.now :: es, none))
    -- Every batch ends with the runtime's frame events, as `Runtime.steps` runs them.
    let plan := plan.map fun (h, es, m) => (h, es ++ frameEvents, m)
    match plan with
    | none =>
      return { world := { rt := rt0, seen, host := host0, secure, server := sw, parked, lastLists }, acts := [],
               ran := false, maxNs := 0 }
    | some (host, es, msg) =>
      let w : World t.S Unit := { rt := rt0, seen, host := host0, secure, server := (), parked, lastLists }
      let mut rt := w.rt
      let mut host := host
      let mut acts : Array Action := #[]
      let mut maxNs := 0
      let mut dropped := false
      let mut effects : Array Effect := #[]
      -- Whether the runtime will drop the host's message: a reply to an id it doesn't hold, or
      -- an event of a subscription it stopped.
      let msgDropped := match op with
        | .host (.reply id r) | .host (.stray id r) => (w.rt.world.takeReply id r).isNone
        | .host (.late ..) => true
        | _ => false
      -- The control a press means, so the first pointerDown can be checked for a T33 drop.
      let pressed? : Option ControlRef := match op with
        | .act (.press c) | .act (.doublePress c) => some c
        | _ => none
      for e in es do
        if let .clock tm := e then
          let due := (rt.world.tick tm).dueNames.length
          host := { host with stats := { host.stats with timersDue := host.stats.timersDue + due } }
        let routed := (route cfg.metrics rt e).2
        let t0 ← IO.monoNanosNow
        let (rt', effs) ← IO.lazyPure fun _ => step app cfg rt e
        -- Force the new laid tree before reading the clock.
        let _ ← IO.lazyPure fun _ => (targets rt'.laid).length
        let t1 ← IO.monoNanosNow
        maxNs := max maxNs (t1 - t0)
        if let (some c, .pointerDown p _ 1 _) := (pressed?, e) then
          if routed.any (· matches .blur _) && hitRef rt'.laid p != some c then dropped := true
        acts := acts ++ routed.toArray
        host := host.after rt.world.subs rt' effs
        effects := effects ++ effs.toArray
        rt := { rt' with subCmds := #[] }
      return { world := { rt, seen, host, secure, server := sw, parked, lastLists }, acts := acts.toList, ran := true,
               maxNs, dropped, msg, effects := effects.toList, msgDropped }

/-! ## Checks -/

/-- Keys to probe for a move: those on screen, the largest seen so far, and one past it. -/
def probeKeys (t : Target) (w : World t.S W) (id : ClaimId) : List Nat :=
  if !t.isKeyed id then [0] else
  let shown := refs w.rt.laid ++ (statusControls w.rt).map (·.2.1)
  let onScreen := shown.filterMap fun r => if r.claim = id then some r.key else none
  let top := (w.seen.get? id).getD 0
  let top := onScreen.foldl max top
  -- Each virtual list's first and last keys, and the keys either side of the rows it laid.
  let rowKeys := (listsOf w.rt.laid).flatMap fun ll =>
    let ks := ll.info.keys
    [ks[0]?, ks.back?, if 0 < ll.info.first then ks[ll.info.first - 1]? else none,
     ks[ll.info.last]?].filterMap fun x => x
  (onScreen ++ [top, top + 1, 0] ++ rowKeys).eraseDups

def World.noteSeen (w : World S W) (laid : Laid) : World S W :=
  { w with seen := (refs laid ++ (statusControls w.rt).map (·.2.1)).foldl (fun m r => m.insert r.claim (max r.key ((m.get? r.claim).getD 0))) w.seen,
           secure := (w.secure ++ secureRefs laid).eraseDups }

def isPointer (m : Move S) : Bool := m.triggers.any fun tr => tr == .press || tr == .doublePress

mutual
/-- The first node, in paint order, that breaks one of `Pressable`'s conditions, and which. -/
def firstBad (l : Laid) : Option (String × Laid) :=
  if !fitsB l then some ("a container's children don't fit it", l)
  else if !stackTopB l then some ("a stack has controls below its top child", l)
  else if !controlLeafB l then some ("a control has controls inside it", l)
  else match l with
    | .box _ _ _ _ kids => firstBadList kids
    | _ => none
def firstBadList : List Laid → Option (String × Laid)
  | [] => none
  | k :: ks => (firstBad k).orElse fun _ => firstBadList ks
end

/-! ### Virtual lists (docs/fuzz.md, "Virtual lists") -/

/-- The index of key `k` among a laid list's keys, if it is one. -/
def _root_.Cairn.Runtime.LaidList.indexOf (ll : LaidList) (k : Nat) : Option Nat := ll.info.keys.findIdx? (· == k)

/-- Whether the list laid its row `i`. -/
def _root_.Cairn.Runtime.LaidList.laidAt (ll : LaidList) (i : Nat) : Bool := ll.info.first ≤ i && i < ll.info.last

/-- The rows the list laid, each with its index: its children between the two spacers. -/
def _root_.Cairn.Runtime.LaidList.rows (ll : LaidList) : List (Nat × Laid) :=
  ((ll.kids.drop 1).take (ll.info.last - ll.info.first)).zipIdx.map fun (k, j) => (ll.info.first + j, k)

/-- The top of the list's content box, on screen. -/
def _root_.Cairn.Runtime.LaidList.contentTop (ll : LaidList) : Int := (ll.rect.inset ll.pad).y

/-- `k` is the key of a row of a list on screen that the list didn't lay. -/
def hiddenRow (lists : List LaidList) (k : Nat) : Bool :=
  lists.any fun ll => match ll.indexOf k with
    | some i => !ll.laidAt i
    | none => false

/-- The moves with a control in a laid row of a list, keyed by the row's key: their controls
show exactly when their row is laid. -/
def rowClaims (lists : List LaidList) : List ClaimId :=
  (lists.flatMap fun ll => ll.rows.flatMap fun (i, k) =>
    let key := ll.info.keys[i]?.getD 0
    (refs k).filterMap fun r => if r.key == key then some r.claim else none).eraseDups

/-- `lastLists` after a frame: each list on screen replaces what was known of it. -/
def noteLists (known lists : List LaidList) : List LaidList :=
  known.filter (fun ll => !lists.any (·.ref == ll.ref)) ++ lists

/-- What is wrong with a laid list, if anything: the rows laid are exactly those whose extent
meets the viewport widened by the overscan, in the heights the view laid out by (`Model.top`,
the specification, not the fast path the view used; `VList.node_rows`); there are no more than
`(viewport + 2·overscan) / minHeight + 2` of them; and the spacers and rows are one under the
other from the content's top less the offset (`Layout.vlist_stacked`). -/
def vlistFault (ll : LaidList) : Option String := Id.run do
  let info := ll.info
  let M := info.modelOf
  let o := ll.offset
  let lo := o - info.overscan
  let hi := o + info.viewport + info.overscan
  let meets (i : Nat) : Bool := decide (lo < M.top i + M.height i) && decide (M.top i < hi)
  let (f, l) := (info.first, info.last)
  unless f ≤ l && l ≤ M.count do
    return some s!"it laid rows [{f}, {l}) of {M.count}"
  if let some i := (List.range' f (l - f)).find? (!meets ·) then
    return some s!"it laid row {i} at [{M.top i}, {M.top i + M.height i}), which misses [{lo}, {hi})"
  if 0 < f && meets (f - 1) then
    return some s!"it didn't lay row {f - 1} at [{M.top (f - 1)}, {M.top f}), which meets [{lo}, {hi})"
  if l < M.count && meets l then
    return some s!"it didn't lay row {l} at [{M.top l}, {M.top (l + 1)}), which meets [{lo}, {hi})"
  let bound := (info.viewport + 2 * info.overscan) / (max 1 M.minHeight : Nat) + 2
  unless ((l - f : Nat) : Int) ≤ bound do
    return some s!"it laid {l - f} rows, more than (viewport + 2·overscan) / minHeight + 2 = {bound}"
  unless ll.kids.length == l - f + 2 do
    return some s!"it has {ll.kids.length} children for {l - f} rows and two spacers"
  let mut y := ll.contentTop - o
  for k in ll.kids do
    unless k.rect.y == y do
      return some s!"a child is at y {k.rect.y}, not {y} where the one before it ends"
    y := k.rect.y + k.rect.h
  return none

/-- A laid row whose height isn't the one the view laid the list out by: the runtime hadn't
recorded it yet when `settle` ran out (`Runtime.settleFuel`). -/
def unsettledRow (ll : LaidList) : Option (Nat × Int × Int) :=
  (ll.rows.find? fun (i, k) => decide (max 1 k.rect.h ≠ ll.info.modelOf.height i)).map
    fun (i, k) => (i, k.rect.h, ll.info.modelOf.height i)

/-- The first row of a laid list that shows: its key and its top, relative to the content's top. -/
def _root_.Cairn.Runtime.LaidList.anchor (ll : LaidList) : Option (Nat × Int) :=
  (ll.rows.find? fun (_, k) => ll.contentTop < k.rect.y + k.rect.h).map
    fun (i, k) => (ll.info.keys[i]?.getD 0, k.rect.y - ll.contentTop)

/-- An operation that may scroll or resize, after which the anchor needn't stay still. -/
def Op.moves : Op → Bool
  | .scroll .. | .key .. | .tab _ | .resize _ => true
  | _ => false

/-- A step's scroll requests, the last for each box. -/
def lastScrolls (effects : List Effect) : List (ControlRef × ScrollTarget) :=
  (requestedScrolls effects).foldl (fun acc (r, t) => (r, t) :: acc.filter (·.1 != r)) []

/-- **`scrollTo` lands** (`Runtime.aimOff_start`, `aimOff_finish`, `aimOff_key`,
`firstF_top`). After a step that asked for it, a box on screen is at 0 for `start` and at its
limit for `finish`; for `key k`, the row with key `k` is the first showing, at the top of the
box, unless the clamp holds the list at its end. -/
def scrollToChecks (laid : Laid) (ui : UI) (effects : List Effect) (stepIx : Nat) :
    List Ran × List Failure := Id.run do
  let mut ran : Array Ran := #[]
  let mut fails : Array Failure := #[]
  for (r, t) in lastScrolls effects do
    let some sc := (scrollersOf laid).find? (·.ref == r) | continue
    ran := ran.push (r.claim, "scrollTo")
    let o := ui.scrollOf r
    match t with
    | .start =>
      unless o == 0 do
        fails := fails.push <| mkFail "scrollTo" r stepIx s!"scrollTo {r.label} start left it at offset {o}"
    | .finish =>
      unless o == sc.limit do
        fails := fails.push <| mkFail "scrollTo" r stepIx
          s!"scrollTo {r.label} end left it at offset {o}, not its limit {sc.limit} (content {sc.content}, viewport {sc.viewport})"
    | .key k =>
      let some ll := (listsOf laid).find? (·.ref == r) | continue
      unless ll.info.keys.contains k do continue
      if o == ll.limit then continue
      match ll.anchor with
      | some (k', y) =>
        unless k' == k && y == 0 do
          fails := fails.push <| mkFail "scrollTo" r stepIx
            s!"scrollTo {r.label} key {k}: the first row showing is {k'}, {y} points into the box (offset {o}, limit {ll.limit})"
      | none =>
        fails := fails.push <| mkFail "scrollTo" r stepIx s!"scrollTo {r.label} key {k}: no row shows"
  return (ran.toList, fails.toList)

/-- **A kept list comes back where it was** (`Runtime.fixUI_keeps_offset`,
`fixUI_keeps_list`). A virtual list the app keeps (`App.keepScroll`) that leaves the view keeps
its offset while it is away, and when it comes back the row that was first showing when it left
is first showing again, at the same place in the box, unless the clamp moved it (to 0 or the
limit) or the row is gone. Returns the lists parked now. -/
def keptChecks (keep : List ControlRef) (ui0 ui : UI) (before after : List LaidList)
    (parked : List (ControlRef × Nat × Int)) (stepIx : Nat) :
    List Ran × List Failure × List (ControlRef × Nat × Int) := Id.run do
  let mut ran : Array Ran := #[]
  let mut fails : Array Failure := #[]
  let mut park : Array (ControlRef × Nat × Int) := #[]
  for r in keep do
    match after.find? (·.ref == r) with
    | none =>
      -- Away: its offset is the one it had.
      ran := ran.push (r.claim, "kept")
      unless ui.scrollOf r == ui0.scrollOf r do
        fails := fails.push <| mkFail "kept" r stepIx
          s!"{r.label} is kept and not on screen, but its offset went from {ui0.scrollOf r} to {ui.scrollOf r}"
      match before.find? (·.ref == r) with
      | some ll0 => if let some (k, y) := ll0.anchor then park := park.push (r, k, y)
      | none => if let some p := parked.find? (·.1 == r) then park := park.push p
    | some ll =>
      if before.any (·.ref == r) then continue
      let some (_, key, y0) := parked.find? (·.1 == r) | continue
      ran := ran.push (r.claim, "kept")
      if ll.offset == 0 || ll.offset == ll.limit then continue
      let some i := ll.indexOf key | continue
      let some (_, k) := ll.rows.find? (·.1 == i) | continue
      let y := k.rect.y - ll.contentTop
      unless y == y0 do
        fails := fails.push <| mkFail "kept" r stepIx
          s!"{r.label} came back with row {key}, first showing when it left at {y0}, at {y} in the box (offset {ll.offset}, limit {ll.limit})"
  return (ran.toList, fails.toList, park.toList)

/-- **The anchor stays still.** Over an operation that doesn't scroll or resize, the first row
showing in each virtual list keeps its place in the box, wherever rows were inserted or heights
changed above it (`VList.record_keeps`), unless the clamp moved the offset (to 0 or the
limit) or the row is gone. -/
def anchorChecks (before after : List LaidList) (op : Op) (stepIx : Nat)
    (effects : List Effect := []) : List Ran × List Failure := Id.run do
  if op.moves then return ([], [])
  let mut ran : Array Ran := #[]
  let mut fails : Array Failure := #[]
  let aimed := (requestedScrolls effects).map (·.1)
  for ll in after do
    -- A list the step asked to scroll moves by design (`scrollToChecks`).
    if aimed.contains ll.ref then continue
    let some ll0 := before.find? (·.ref == ll.ref) | continue
    let some (key, y0) := ll0.anchor | continue
    ran := ran.push (ll.ref.claim, "anchor")
    if ll.offset == 0 || ll.offset == ll.limit then continue
    let some i := ll.indexOf key | continue
    let some (_, k) := ll.rows.find? (·.1 == i) | continue
    let y := k.rect.y - ll.contentTop
    unless y == y0 do
      fails := fails.push <| mkFail "anchor" ll.ref stepIx
        s!"row {key}, the first showing in {ll.ref.label}, moved from {y0} to {y} in the box (offset {ll0.offset} → {ll.offset}, limit {ll.limit})"
  return (ran.toList, fails.toList)

/-- The check name a dropped click is counted under (`Performed.dropped`). -/
def droppedCheck : String := "droppedT33"

/-- Every check after an operation: the checks that ran and the failures. `act?` is the
action the operation meant to perform, if it ran. -/
def checks (t : Target) (setup : Setup) (w : World t.S W) (act? : Option Action)
    (acts : List Action) (stepIx : Nat) (dropped : Bool := false) (effects : List Effect := []) :
    List Ran × List Failure := Id.run do
  let s := w.rt.app
  let mut ran : Array Ran := #[]
  let mut fails : Array Failure := #[]
  -- Invariants.
  for inv in t.invariants do
    if let some ck := inv.check then
      ran := ran.push (inv.info.id, "invariant")
      unless ck s do
        fails := fails.push <| mkFail "invariant" ⟨inv.info.id, 0⟩ stepIx
          s!"^{inv.info.id} {inv.info.title} is false after this step"
  let some app := t.app | return (ran.toList, fails.toList)
  -- Outstanding: the app's checks against the requests the runtime still holds for it.
  unless t.custom.outstanding.isEmpty do
    let ids := w.rt.world.entries.map (·.1)
    for (id, ck) in t.custom.outstanding do
      ran := ran.push (id, "outstanding")
      unless ck s ids do
        fails := fails.push <| mkFail "outstanding" ⟨id, 0⟩ stepIx
          s!"^{id} is false after this step, with the runtime holding {ids.length} requests for the app: {ids.map (s!"#{·}")}"
  -- The Dock badge: the app's checks against the label the host shows (^1030).
  for (id, ck) in t.custom.badge do
    ran := ran.push (id, "badge")
    unless ck s w.host.badge do
      fails := fails.push <| mkFail "badge" ⟨id, 0⟩ stepIx
        s!"^{id} is false after this step, with the Dock badge {reprStr w.host.badge}"
  let laid := w.rt.laid
  let m := setup.metrics.metrics
  let size := w.rt.ui.size
  let min := t.minSize m s w.rt.ui
  let fitsWindow := decide (min.w ≤ size.w) && decide (min.h ≤ size.h)
  -- Performed: the action meant was delivered, unless the click was dropped by design (T33).
  if let some a := act? then
    let c := a.control
    if dropped && !acts.contains a then
      ran := ran.push (c.claim, droppedCheck)
    else if fitsWindow then
      ran := ran.push (c.claim, "performed")
      unless acts.contains a do
        fails := fails.push <| mkFail "performed" c stepIx
          s!"{reprStr (redactAction w.secure a)} was meant, but the runtime delivered {reprStr (acts.map (redactAction w.secure))}"
  -- Presence: a control is in the frame iff its move is enabled, and, for a move whose controls
  -- live in a virtual list's rows, its row is laid. A control keyed like a row the list didn't
  -- lay may be missing, and so may one keyed like a row of a list off screen (hidden while the
  -- app keeps it, `App.keepScroll`): none of its rows is laid.
  let lists := listsOf laid
  let inRows := rowClaims lists
  let away := w.lastLists.filter fun ll => !lists.any (·.ref == ll.ref)
  let awayRows := rowClaims away
  for mv in t.machine.moves do
    if t.custom.noControl.contains mv.id then continue
    ran := ran.push (mv.id, "presence")
    for k in probeKeys t w mv.id do
      let r : ControlRef := ⟨mv.id, k⟩
      let on := present laid r || onStatus w.rt r
      let en := mv.enabled s k
      let hid := hiddenRow lists k || awayRows.contains mv.id || away.any fun ll => (ll.indexOf k).isSome
      let ok := if inRows.contains mv.id then on == (en && !hid)
        else if hid then !on || en else on == en
      unless ok do
        fails := fails.push <| mkFail "presence" r stepIx
          (if !on then s!"{r.label} is enabled{if inRows.contains mv.id then " and its row is laid" else ""} but has no control in the frame"
           else if !en then s!"{r.label} is in the frame but its move is disabled"
           else s!"{r.label} is in the frame, but its row is not laid")
  -- Virtual lists: the rows laid, how many, one under the other, at their real heights.
  for ll in lists do
    ran := ran.push (ll.ref.claim, "vlist")
    if let some why := vlistFault ll then
      fails := fails.push <| mkFail "vlist" ll.ref stepIx s!"{ll.ref.label}: {why}"
    if let some (i, h, hm) := unsettledRow ll then
      fails := fails.push <| mkFail "vlist" ll.ref stepIx
        s!"{ll.ref.label}: row {i} is laid {h} high but laid out as {hm}: its height wasn't recorded before the frame"
  -- Images: everything the frame draws is held by the host. An app takes an image for ready
  -- only from the host's answer and forgets it when told it was dropped (^1006, ^1011;
  -- `Images.Cache.ready_held`); a draw of a source the host doesn't hold paints nothing.
  let drawn := drawnBy w.rt
  unless drawn.isEmpty do
    let place := app.windowPlace.getD 0
    ran := ran.push (place, "image")
    for src in drawn.eraseDups do
      unless (w.host.heldOf src).isSome do
        fails := fails.push <| mkFail "image" ⟨place, 0⟩ stepIx
          s!"the frame draws {src.quote}, whose pixels the host doesn't hold (never loaded, or dropped with no `evicted` the app heeded)"
  -- Secure fields: the planted text (`Text.planted`, typed into secure fields only) is in no
  -- dump of the frame and no dump of the step's effects (a request carrying it must be
  -- redacted, `Request.redact`).
  -- Dumps print bytes as hex, so the planted text is looked for as text and as hex.
  let plantedIn (d : String) : Bool :=
    Dump.occurs Text.planted d || Dump.occurs ((Dump.bytes Text.planted.toUTF8).drop 1).toString d
  -- Once a secure field has been seen, every later frame and effect is checked too: its text
  -- must not turn up after the field is gone either.
  if let some r := (secureRefs laid).head?.orElse fun _ => w.secure.head? then
    ran := ran.push (r.claim, "secure")
    if plantedIn (Dump.canvas (Frame.ofLaid w.rt.ui laid)) then
      fails := fails.push <| mkFail "secure" r stepIx
        s!"the frame's dump holds text typed into the secure field {r.label}"
    for e in effects do
      if plantedIn (Dump.effect e) then
        fails := fails.push <| mkFail "secure" r stepIx
          s!"an effect's dump holds text typed into the secure field {r.label} (an unredacted request?)"
  -- Scrolling: every scroll box's offset is within [0, max 0 (content − viewport)], the box is
  -- laid at the runtime's offset, and the runtime keeps no offset for a box that isn't there
  -- (`Runtime.step_clamped`).
  for sc in scrollersOf laid do
    ran := ran.push (sc.ref.claim, "scroll")
    let o := w.rt.ui.scrollOf sc.ref
    unless 0 ≤ o && o ≤ sc.limit do
      fails := fails.push <| mkFail "scroll" sc.ref stepIx
        s!"{sc.ref.label}'s offset {o} is outside [0, {sc.limit}] (content {sc.content}, viewport {sc.viewport})"
    unless sc.offset == o do
      fails := fails.push <| mkFail "scroll" sc.ref stepIx
        s!"{sc.ref.label} is laid at offset {sc.offset}, but the runtime's offset is {o}: the view should pass `ui.scrollOf` (`UI.scrolling`)"
  for (r, o) in w.rt.ui.scroll do
    unless (scrollersOf laid).any fun sc => sc.ref == r do
      fails := fails.push <| mkFail "scroll" r stepIx
        s!"the runtime keeps offset {o} for {r.label}, which is no scroll box on screen"
  -- Appear: each appear move the frame delivered names a move that answers it.
  for a in acts do
    if let .appear c := a then
      ran := ran.push (c.claim, "appear")
      unless (t.move? c.claim).any (·.triggers.contains .appear) do
        fails := fails.push <| mkFail "appear" c stepIx
          s!"{c.label} came on screen, but no move answers `appear` for it: mark only controls of moves with `on appear` (`Control.appear`)"
  -- Pressable, at sizes at or above the minimum.
  if fitsWindow then
    let ts := targets laid
    let mut anyPointer := none
    for tg in ts do
      if tg.isField then continue
      -- Scrolled out of view: no part of it to press (`not_hit_of_hidden`).
      unless decide tg.visible.nonempty do continue
      let some mv := t.move? tg.ref.claim | continue
      unless isPointer mv && mv.enabled s tg.ref.key do continue
      if anyPointer.isNone then anyPointer := some tg.ref
      ran := ran.push (tg.ref.claim, "pressable")
      let hit := hitRef laid tg.visible.center
      unless hit == some tg.ref do
        fails := fails.push <| mkFail "pressable" tg.ref stepIx
          s!"{tg.ref.label}'s centre {reprStr tg.visible.center} hits {reprStr (hit.map (·.label))} at {size.w}×{size.h}"
    if let some r := anyPointer then
      unless checkPressable size laid && controlRectsNonempty laid do
        -- Blame the first control inside the first node that breaks a condition.
        let (why, r) := match firstBad laid with
          | some (why, n) => (why, (n.controls.head?.map fun (c : Control) => c.ref).getD r)
          | none =>
            if !insideB laid.rect (windowRect size) then ("the root is outside the window", r)
            else ("a control's rect is empty", ((targets laid).find? fun (tg : Cairn.Runtime.Target) =>
              !(decide (0 < tg.node.rect.w) && decide (0 < tg.node.rect.h))).map Cairn.Runtime.Target.ref |>.getD r)
        fails := fails.push <| mkFail "pressable-check" r stepIx
          s!"Layout.checkPressable rejects the tree at {size.w}×{size.h} (window ≥ minimum {min.w}×{min.h}): {why}, near {r.label}"
  return (ran.toList, fails.toList)

/-! ## Generating operations -/

/-- The actions available now: for each control on screen whose move is enabled, each trigger
it can take there, and a press on each enabled status-item control (`statusControls`). Without
an `App`, each enabled move and probed key. -/
def candidates (t : Target) (w : World t.S W) : List (ControlRef × Trigger × Bool) :=
  let s := w.rt.app
  match t.app with
  | some _ =>
    let onStatusItems := (statusControls w.rt).flatMap fun (_, r, e) =>
      match t.move? r.claim with
      | some mv => if e && mv.enabled s r.key && mv.triggers.contains .press then [(r, Trigger.press, false)] else []
      | none => []
    onStatusItems ++ (targets w.rt.laid).flatMap fun tg =>
      match t.move? tg.ref.claim with
      | none => []
      | some mv =>
        if !mv.enabled s tg.ref.key || !decide tg.visible.nonempty then [] else
        mv.triggers.filterMap fun tr =>
          let ok := if tr == .appear then false
                    else if tg.isField then tr != .press && tr != .doublePress
                    else tr == .press || tr == .doublePress
          if ok then some (tg.ref, tr, tg.isField) else none
  | none =>
    t.machine.moves.flatMap fun mv =>
      let keys := if t.isKeyed mv.id then List.range 17 else [0]
      keys.flatMap fun k =>
        if mv.enabled s k then mv.triggers.map fun tr => (⟨mv.id, k⟩, tr, tr == .edit) else []

def textScript (t : Target) (s : t.S) (id : ClaimId) : Gen (List TextOp) :=
  (t.custom.edits s id).getD Text.script

/-- An action of a control on screen, picked in proportion to the control's weight
(`Custom.weights`, default 1; 0 never). `none` when nothing can be picked. -/
def genAct (t : Target) (w : World t.S W) : Gen (Option (List Op)) := do
  let cs := (candidates t w).map fun x => (t.custom.weights w.rt.app x.1, x)
  let some (c, tr, _) ← Gen.pick cs | return none
  match tr with
  | .press => return some [.act (.press c)]
  | .doublePress => return some [.act (.doublePress c)]
  | .submit => return some [.act (.submit c)]
  | .cancel => return some [.act (.cancel c)]
  | .blur => return some [.act (.blur c)]
  | .appear => return some [.act (.appear c)]
  | .edit =>
    let ops ← textScript t w.rt.app c.claim
    -- Plant text in a secure field, for the "secure" check.
    let ops := if w.secure.contains c && (← Gen.chance 1 3) then .insert Text.planted :: ops else ops
    return some (ops.map fun op => .act (.edit c op))

def genPoint (w : World S W) : Gen Point := do
  let ts := targets w.rt.laid
  let ts := ts.filter fun tg => decide tg.visible.nonempty
  if !ts.isEmpty && (← Gen.bool) then
    let tg ← Gen.elem ts
    let c := tg.visible.center
    return ⟨c.x + (← Gen.int (-6) 6), c.y + (← Gen.int (-6) 6)⟩
  let z := w.rt.ui.size
  return ⟨← Gen.int 0 (max 0 z.w), ← Gen.int 0 (max 0 z.h)⟩

/-- A window size at or above the minimum, or (one in twenty) below it. -/
def genSize (min : Size) : Gen Size := do
  if ← Gen.chance 1 20 then
    return ⟨← Gen.int 0 (max 0 min.w), ← Gen.int 0 (max 0 min.h)⟩
  return ⟨min.w + (← Gen.int 0 400), min.h + (← Gen.int 0 400)⟩

/-- A wheel or trackpad scroll: mostly at a point in a scroll box, by a tick, a flick or (one in
eight) far past either end, to test the clamp; sometimes sideways. -/
def genScroll (w : World S W) : Gen Op := do
  let scs := (scrollersOf w.rt.laid).filter fun sc => decide sc.visible.nonempty
  let p ← if !scs.isEmpty && (← Gen.chance 3 4) then do
      let sc ← Gen.elem scs
      let v := sc.visible
      pure (⟨v.x + (← Gen.int 0 (max 0 (v.w - 1))), v.y + (← Gen.int 0 (max 0 (v.h - 1)))⟩ : Point)
    else genPoint w
  let d ← Gen.weighted
    [ (5, Gen.int (-48) 48), (3, Gen.int (-1200) 1200),
      (1, do return if ← Gen.bool then 1_000_000 else -1_000_000) ]
  if ← Gen.chance 1 6 then return .scroll p d 0
  return .scroll p (← Gen.int (-3) 3) d

/-- The keys that scroll (docs/runtime.md, "Scrolling"). -/
def scrollKeys : List Key := [.pageUp, .pageDown, .home, .finish, .up, .down, .left, .right, .char ' ']

def genNoise (t : Target) (setup : Setup) (w : World t.S W) : Gen (List Op) := do
  if t.app.isNone then return []
  let scrolls := if (scrollersOf w.rt.laid).isEmpty then 1 else 8
  Gen.weighted
    [ (scrolls, do return [← genScroll w]),
      (scrolls / 2, do return [.key (← Gen.elem scrollKeys) { shift := ← Gen.chance 1 4,
                                                                 command := ← Gen.chance 1 8 }]),
      (6, do return [.click (← genPoint w) (← Gen.elem [1, 1, 1, 2])]),
      (4, do return [.move (← genPoint w)]),
      (5, do return [.tab (← Gen.chance 1 4)]),
      (5, do return [.key (← Gen.elem [.enter, .escape, .backspace, .left, .right, .tab])
                            { shift := ← Gen.chance 1 4 }]),
      (6, do return [.resize (← genSize (t.minSize setup.metrics.metrics w.rt.app w.rt.ui))]),
      (1, pure [.exit]),
      (2, do return [.windowFocus (← Gen.chance 3 4)]) ]

/-- The next operations: the host's move (`Host.share`: one time in five or more while it has
something to say, a request, a timer or a subscription, one in thirty otherwise); else mostly an enabled
action, otherwise pointer, key or window noise. -/
def genOps (t : Target) (setup : Setup) (w : World t.S W) : Gen (List Op) := do
  if t.app.isSome then
    if ← Gen.chance (w.host.share w.rt) 100 then
      return [.host (← genHost t.custom w.host w.rt)]
  if t.app.isNone || (← Gen.chance 7 10) then
    if let some ops ← genAct t w then return ops
  genNoise t setup w

/-- A sequence's setup from its seed: metrics, then a window at or above the initial minimum. -/
def genSetup (t : Target) (seed : Nat) : Setup × Rng :=
  let g : Gen Setup := do
    let metrics ← MetricsChoice.gen
    let m := metrics.metrics
    let min := t.minSize m t.machine.init {}
    let size : Size := ⟨min.w + (← Gen.int 0 400), min.h + (← Gen.int 0 400)⟩
    let mono ← Gen.range 0 1_000_000_000
    let wall : Int := 1_792_749_600_000 + ((← Gen.below 1_000_000_000_000) : Int)
    let zone ← Gen.elem [0, 3600, -18_000, -28_800, 19_800, 32_400, 45_900]
    let start : Time := { mono, wall, zone }
    return { seed, size, metrics, start }
  g.run (Rng.ofSeed seed)

/-- The app's checks over one step (`Custom.relations`), from state `s0` by the host's message
`msg` (`none` for a person's operation) to `s1`. -/
def relationChecks (t : Target) (tr : Transition t.S) (stepIx : Nat) (direct : Bool := false) :
    List Ran × List Failure :=
  let sent := match tr.msg with
    | some m => s!" (the host sent {reprStr m}{if direct then ", which the runtime drops, straight to receive" else ""})"
    | none => ""
  t.custom.relations.foldl (fun (ran, fs) (id, rel) =>
    (ran ++ [(id, "relation")],
     if rel tr then fs
     else fs ++ [mkFail "relation" ⟨id, 0⟩ stepIx s!"^{id} fails over this step{sent}"]))
    ([], [])

/-- The host answers everything outstanding, oldest first, with the app's replies (or the
default), until nothing is or `fuel` runs out. Returns the world and how many replies it sent. -/
def drain (t : Target) (setup : Setup) (w : World t.S t.W) (rng : Rng) (fuel : Nat) :
    IO (World t.S t.W × Nat) := do
  let mut w := w
  let mut rng := rng
  let mut n := 0
  for _ in [0:fuel] do
    let some (id, r) := w.host.sent.head? | break
    -- A request the server takes reaches it first, if it hasn't, then gets its reply: no
    -- faults once the sequence is over.
    if t.srv.takes r then
      if (w.host.ready.lookup id).isNone then
        let (sd, rng') := Gen.seed.run rng
        rng := rng'
        w := (← perform t setup w (.host (.serve id sd))).world
      let rep := (w.host.ready.lookup id).getD .done
      w := (← perform t setup w (.host (.reply id rep))).world
      n := n + 1
      continue
    let gen : Gen Reply := if w.host.isCancelled id then genCancelled t.custom w.rt.app w.host id r
      else match w.host.ready.lookup id with
        | some rep => pure rep
        | none => genReply t.custom w.rt.app w.host id r
    let (rep, rng') := gen.run rng
    rng := rng'
    let p ← perform t setup w (.host (.reply id rep))
    w := p.world
    n := n + 1
  return (w, n)

/-- The server's checks (`Server.checks`) on the app's state and the world: the checks that ran
and the failures, each failure's message naming the world (`Server.describe`). -/
def serverChecks (t : Target) (w : World t.S t.W) (stepIx : Nat) (kind : String)
    (cks : List (ClaimId × (t.S → t.W → Bool))) (after : String) : List Ran × List Failure :=
  cks.foldl (fun (ran, fs) (id, ck) =>
    (ran ++ [(id, kind)],
     if ck w.rt.app w.server then fs else
     let d := t.srv.describe w.server
     fs ++ [mkFail kind ⟨id, 0⟩ stepIx
       s!"^{id} is false {after}, against the server's world{if d.isEmpty then "" else s!": {d}"}"]))
    ([], [])

/-! ## Running a sequence -/

/-- Counters for one claim. -/
structure ClaimStat where
  steps : Nat := 0
  checks : Std.HashMap String Nat := {}
  sequences : Nat := 0
  /-- The last sequence that touched it, so `sequences` counts each once. -/
  lastSeq : Option Nat := none
deriving Inhabited

abbrev Stats := Std.HashMap ClaimId ClaimStat

def Stats.record (st : Stats) (seq : Nat) (ran : List Ran) : Stats := Id.run do
  let mut st := st
  let mut touched : Std.HashSet ClaimId := {}
  for (id, kind) in ran do
    let c := (st.get? id).getD {}
    let c := { c with checks := c.checks.insert kind ((c.checks.get? kind).getD 0 + 1) }
    let c := if touched.contains id then c else
      { c with
        steps := c.steps + 1
        sequences := if c.lastSeq == some seq then c.sequences else c.sequences + 1
        lastSeq := some seq }
    touched := touched.insert id
    st := st.insert id c
  return st

/-- What one sequence did. -/
structure Outcome where
  setup : Setup
  ops : Array Op
  failure : Option Failure
  stats : Stats
  steps : Nat
  /-- Steps over the frame budget: (step, nanoseconds). -/
  over : Array (Nat × Nat)
  maxNs : Nat
  /-- Steps where pressability was skipped because the window was below the minimum. -/
  skipped : Nat
  /-- What the host did. -/
  host : HostStats := {}
  /-- The secure fields seen, whose edits are printed redacted. -/
  secure : List ControlRef := []

/-- Where a sequence's operations come from: the generator, or a fixed list (replay). -/
inductive Source where
  | gen (rng : Rng) (steps : Nat)
  | replay (ops : Array Op)

/-- Run one sequence, stopping at the first failure. Verbose prints each step. -/
def runSeq (t : Target) (setup : Setup) (src : Source) (stats : Stats := {})
    (verbose : Bool := false) : IO Outcome := do
  let mut w := (World.start t setup).noteSeen (World.start t setup).rt.laid
  w := { w with lastLists := listsOf w.rt.laid }
  let mut stats := stats
  let mut ops : Array Op := #[]
  let mut over : Array (Nat × Nat) := #[]
  let mut maxNs := 0
  let mut skipped := 0
  -- The initial state is checked too.
  let (ran0, f0) := checks t setup w none [] 0
  let (ranS, fS) := serverChecks t w 0 "server" t.srv.checks "in the first frame"
  let (ran0, f0) := (ran0 ++ ranS, f0 ++ fS)
  stats := stats.record setup.seed ran0
  if let some f := f0.head? then
    return { setup, ops, failure := some f, stats, steps := 0, over, maxNs, skipped, host := w.host.stats, secure := w.secure }
  let (rng0, total, fixed) := match src with
    | .gen r n => (r, n, #[])
    | .replay os => (Rng.ofSeed 0, os.size, os)
  let mut rng := rng0
  let mut pending : List Op := []
  let mut i := 0
  while i < total do
    let op ← match pending, src with
      | o :: rest, _ => pending := rest; pure o
      | [], .replay _ => pure fixed[i]!
      | [], .gen .. =>
        let (os, r) := (genOps t setup w).run rng
        rng := r
        match os with
        | o :: rest => pending := rest; pure o
        | [] => pure Op.exit
    ops := ops.push op
    let s0 := w.rt.app
    let ui0 := w.rt.ui
    let lists0 := listsOf w.rt.laid
    let p ← perform t setup w op
    i := i + 1
    w := p.world.noteSeen p.world.rt.laid
    w := { w with lastLists := noteLists w.lastLists (listsOf w.rt.laid) }
    maxNs := max maxNs p.maxNs
    if p.maxNs > t.budgetNs then over := over.push (i, p.maxNs)
    let act? := match op with | .act a => if p.ran then some a else none | _ => none
    let (ran, fs) := checks t setup w act? p.acts i p.dropped p.effects
    let (ran, fs) := let (r4, f4) := anchorChecks lists0 (listsOf w.rt.laid) op i p.effects; (ran ++ r4, fs ++ f4)
    let (ran, fs) := let (r5, f5) := scrollToChecks w.rt.laid w.rt.ui p.effects i; (ran ++ r5, fs ++ f5)
    let (ran, fs) ← match t.app with
      | some app =>
        let (r6, f6, park) := keptChecks (app.keepScroll w.rt.app) ui0 w.rt.ui lists0
          (listsOf w.rt.laid) w.parked i
        w := { w with parked := park }
        pure (ran ++ r6, fs ++ f6)
      | none => pure (ran, fs)
    let (ran, fs) := let (r7, f7) := serverChecks t w i "server" t.srv.checks "after this step"; (ran ++ r7, fs ++ f7)
    let (ran, fs) := if p.ran && !t.custom.relations.isEmpty then
        let (r2, f2) := relationChecks t { before := s0, msg := p.msg, after := w.rt.app, effects := p.effects } i
        -- A message the runtime dropped is also given to `receive` directly.
        let (r3, f3) := match p.msg, p.msgDropped with
          | some m, true =>
            let (s1, es) := t.runApp.receive s0 m
            relationChecks t { before := s0, msg := some m, after := s1, effects := es } i true
          | _, _ => ([], [])
        (ran ++ r2 ++ r3, fs ++ f2 ++ f3)
      else (ran, fs)
    if t.app.isSome then
      let min := t.minSize setup.metrics.metrics w.rt.app w.rt.ui
      unless min.w ≤ w.rt.ui.size.w && min.h ≤ w.rt.ui.size.h do skipped := skipped + 1
    stats := stats.record setup.seed ran
    if verbose then
      IO.println s!"  {i}. {opText (op.redactIn w.secure)}{if p.ran then "" else "  (skipped: no such control)"} → {", ".intercalate (p.acts.map (actionLean ∘ redactAction w.secure))}{if p.dropped then "  (click dropped: the blur's save moved the control, T33)" else ""}"
    if let some f := fs.head? then
      return { setup, ops, failure := some f, stats, steps := i, over, maxNs, skipped, host := w.host.stats, secure := w.secure }
  -- Once the operations are done, the host answers everything outstanding, if the app has
  -- checks for then.
  if t.app.isSome && (!t.custom.drained.isEmpty || !t.srv.drained.isEmpty) then
    let (w', n) ← drain t setup w (Rng.ofSeed (setup.seed + 0x5eed)) 1000
    w := w'
    let s := w.rt.app
    let mut ran : Array Ran := #[]
    let mut fails : Array Failure := #[]
    let after := s!"once the host has answered everything ({n} more replies, {w.host.sent.length} still unanswered)"
    for (id, ck) in t.custom.drained do
      ran := ran.push (id, "drained")
      unless ck s do
        fails := fails.push <| mkFail "drained" ⟨id, 0⟩ i s!"^{id} is false {after}"
    let (rS, fS) := serverChecks t w i "serverDrained" t.srv.drained after
    ran := ran ++ rS.toArray
    fails := fails ++ fS.toArray
    stats := stats.record setup.seed ran.toList
    if let some f := fails[0]? then
      return { setup, ops, failure := some f, stats, steps := i, over, maxNs, skipped, host := w.host.stats, secure := w.secure }
  let host := { w.host.stats with leftOver := w.host.sent.length }
  return { setup, ops, failure := none, stats, steps := i, over, maxNs, skipped, host, secure := w.secure }

end Cairn.Fuzz
