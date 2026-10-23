import Cairn.Runtime.Step

/-! Theorems about the runtime: actions name controls on screen, interaction state stays
sound, and a click at a reachable control presses it. -/

namespace Cairn.Runtime

variable {S : Type}

/-! ## Routing leaves the app and the tree alone -/

theorem tab_fst (s : State S) (back : Bool) :
    (tab s back).1.laid = s.laid ∧ (tab s back).1.app = s.app := by
  unfold tab; split <;> simp

theorem route_laid (m : TextMetrics) (s : State S) (e : Event) :
    (route m s e).1.laid = s.laid ∧ (route m s e).1.app = s.app := by
  induction e with
  | surface p e ih => simp only [route]; split; exact ih; exact ⟨rfl, rfl⟩
  | _ =>
    rw [route.eq_def] <;> (try simp only [withPointer]) <;> (try split) <;> (try split) <;>
      (try split) <;> (try split) <;> first | contradiction | simp [tab_fst]

/-! ## Interaction state is sound -/

/-- Focus is a focusable control of the tree on screen; hover and press are controls of it. -/
def Sound (s : State S) : Prop :=
  (∀ r, s.ui.focus = some r → ∃ t ∈ targets s.laid, t.ref = r ∧ t.focusable = true) ∧
  (∀ r, s.ui.hover = some r → r ∈ refs s.laid) ∧
  (∀ r, s.ui.pressed = some r → r ∈ refs s.laid)

theorem fixUI_sound (laid : Laid) (pointer : Option Point) (ui : UI) :
    (∀ r, (fixUI laid pointer ui).focus = some r →
      ∃ t ∈ targets laid, t.ref = r ∧ t.focusable = true) ∧
    (∀ r, (fixUI laid pointer ui).hover = some r → r ∈ refs laid) ∧
    (∀ r, (fixUI laid pointer ui).pressed = some r → r ∈ refs laid) := by
  refine ⟨fun r h => ?_, fun r h => ?_, fun r h => ?_⟩
  · simp only [fixUI, Option.filter_eq_some_iff] at h
    obtain ⟨-, h⟩ := h
    simp only [focusableIn, List.any_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨t, ht, e, f⟩ := h
    exact ⟨t, ht, e, f⟩
  · simp only [fixUI, Option.bind_eq_some_iff] at h
    obtain ⟨p, -, h⟩ := h
    exact hitRef_present h
  · simp only [fixUI, Option.filter_eq_some_iff] at h
    obtain ⟨-, h⟩ := h
    simp only [present, List.any_eq_true, decide_eq_true_eq] at h
    obtain ⟨x, hx, rfl⟩ := h
    exact hx

/-- `settle` always returns `ui0` repaired against the tree it returns. -/
theorem settle_spec (app : App S) (cfg : Config) (st : S) (pointer : Option Point) (ui0 : UI) :
    ∀ fuel ui, ∃ l, settle app cfg st pointer ui0 fuel ui = (fixUI l pointer ui0, l)
  | 0, ui => ⟨relayout app cfg st ui, rfl⟩
  | f + 1, ui => by
    simp only [settle]
    split
    · exact ⟨_, rfl⟩
    · exact settle_spec app cfg st pointer ui0 f _

theorem sound_settle (app : App S) (cfg : Config) (st : S) (pointer : Option Point) (ui0 : UI)
    (fuel : Nat) (ui : UI) (s : State S)
    (h : (s.ui, s.laid) = settle app cfg st pointer ui0 fuel ui) : Sound s := by
  obtain ⟨l, hl⟩ := settle_spec app cfg st pointer ui0 fuel ui
  rw [hl] at h
  simp only [Prod.mk.injEq] at h
  obtain ⟨h1, h2⟩ := h
  unfold Sound; rw [h1, h2]; exact fixUI_sound l pointer ui0

/-- **Focus is sound** at start. -/
theorem start_sound (app : App S) (cfg : Config) (size : Size) (scale : Nat) :
    Sound (start app cfg size scale) :=
  sound_settle app cfg app.init none _ settleFuel _ _ rfl

/-- **Focus is sound** after every step: focus is none or a focusable control of the tree on
screen, and hover and press are none or controls of it. -/
theorem step_sound (app : App S) (cfg : Config) (s : State S) (e : Event) (h : Sound s) :
    Sound (step app cfg s e).1 := by
  unfold step
  split
  · rename_i heq
    dsimp only
    split
    · rename_i hc
      simp only [Bool.and_eq_true] at hc
      have hui := UI.same_eq hc.2
      have hl := (route_laid cfg.metrics s e).1
      rw [heq] at hl
      unfold Sound; simp only; rw [hui, hl]; exact h
    · exact sound_settle app cfg _ _ _ _ _ _ rfl

theorem steps_sound (app : App S) (cfg : Config) (s : State S) (es : List Event)
    (h : Sound s) : Sound (steps app cfg s es).1 := by
  unfold steps
  suffices ∀ (es : List Event) (acc : State S × List Effect), Sound acc.1 →
      Sound (es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e')) acc).1 from
    this es (s, []) h
  intro es
  induction es with
  | nil => intro acc h; exact h
  | cons e es ih =>
    intro acc h
    exact ih _ (step_sound app cfg acc.1 e h)

/-! ## No action without a control -/

/-- Every action names a control of `laid`. -/
def Names (laid : Laid) (acts : List Action) : Prop := ∀ a ∈ acts, a.control ∈ refs laid

theorem names_nil (laid : Laid) : Names laid [] := by simp [Names]

theorem names_append {laid : Laid} {a b : List Action} (ha : Names laid a) (hb : Names laid b) :
    Names laid (a ++ b) := by
  intro x hx; rcases List.mem_append.mp hx with h | h
  · exact ha x h
  · exact hb x h

/-- Actions all about one control of the tree. -/
theorem names_of {laid : Laid} {t : Target} (ht : t ∈ targets laid) {acts : List Action}
    (h : ∀ a ∈ acts, a.control = t.ref) : Names laid acts := by
  intro a ha; rw [h a ha]; exact mem_refs ht

theorem focused_mem {s : State S} {t : Target} (h : focused s = some t) : t ∈ targets s.laid := by
  unfold focused at h
  obtain ⟨r, -, hr⟩ := Option.bind_eq_some_iff.mp h
  exact (find_mem hr).1

theorem leave_names (s : State S) (n : Option ControlRef) : Names s.laid (leave s n) := by
  unfold leave
  split
  · rename_i f hf
    split
    · exact names_of (focused_mem hf) (by simp [Action.control])
    · exact names_nil _
  · exact names_nil _

theorem leave_blurs (s : State S) (n : Option ControlRef) :
    ∀ a ∈ leave s n, ∃ c, a = .blur c := by
  unfold leave; split
  · split <;> simp
  · simp

theorem onField_names (s : State S) (ops : Target → List TextOp) :
    Names s.laid (onField s ops) := by
  unfold onField; split
  · rename_i t ht
    split
    · exact names_of (focused_mem ht) (by simp [Action.control])
    · exact names_nil _
  · exact names_nil _

theorem keyActions_names (s : State S) (k : Key) (mods : Mods) :
    Names s.laid (keyActions s k mods) := by
  unfold keyActions; split
  · exact names_nil _
  · rename_i t ht
    apply names_of (focused_mem ht)
    split <;> (try split) <;> simp [Action.control]

theorem textActions_names (s : State S) (str : String) (rep : Option (Nat × Nat)) :
    Names s.laid (textActions s str rep) := by
  unfold textActions; split
  · exact names_nil _
  · rename_i t ht
    apply names_of (focused_mem ht)
    split
    · intro a ha; obtain ⟨o, -, rfl⟩ := List.mem_map.mp ha; rfl
    · split <;> simp [Action.control]

theorem tabTarget_mem (s : State S) (back : Bool) {t : Target} (h : tabTarget s back = some t) :
    t ∈ targets s.laid := by
  unfold tabTarget at h
  dsimp only at h
  have : t ∈ tabOrder s.laid := by
    split at h
    · split at h
      · exact List.mem_of_getLast? h
      · exact List.mem_of_mem_head? h
    · exact List.mem_of_getElem? h
  exact (List.mem_filter.mp this).1

theorem tab_names (s : State S) (back : Bool) : Names s.laid (tab s back).2 := by
  unfold tab; split
  · exact names_nil _
  · rename_i t ht
    exact names_append (leave_names s _)
      (names_of (tabTarget_mem s back ht) (by split <;> simp [Action.control]))

/-- **No action without a control.** Every action the runtime passes to `update` names a
control of the laid tree on screen when the event arrived, unless the event is a menu event
(those name the menu's items: `menu_route_names`). (`step` delivers exactly
`(route cfg.metrics s e).2`.) -/
theorem route_names (m : TextMetrics) (s : State S) (e : Event) (hm : e.isMenu = false) :
    Names s.laid (route m s e).2 := by
  induction e with
  | surface p e ih =>
    simp only [route]; split
    · rename_i h
      simp only [Bool.and_eq_true, decide_eq_true_eq] at h
      refine ih ?_
      cases e <;> simp_all [Event.isLocal, Event.isMenu]
    · exact names_nil _
  | menuOpen _ => simp [Event.isMenu] at hm
  | menuSelect _ _ => simp [Event.isMenu] at hm
  | pointerMove p =>
    simp only [route]; split
    · rename_i t ht
      obtain ⟨r, -, hr⟩ := Option.bind_eq_some_iff.mp ht
      split
      · exact names_of (find_mem hr).1 (by simp [Action.control])
      · exact names_nil _
    · exact names_nil _
  | pointerDown p b clicks mods =>
    cases b with
    | primary =>
      simp only [route]; split
      · rename_i t ht
        split
        · exact names_append (leave_names s _)
            (names_of (hitTarget_mem ht) (by simp [Action.control]))
        · exact leave_names s _
      · exact leave_names s _
    | secondary => exact names_nil _
  | pointerUp p b mods =>
    cases b with
    | primary =>
      simp only [route]; split
      · rename_i t ht
        split
        · exact names_of (hitTarget_mem ht) (by split <;> simp [Action.control])
        · exact names_nil _
      · exact names_nil _
    | secondary => exact names_nil _
  | key k mods =>
    cases k <;> simp only [route] <;>
      first | exact tab_names s _ | exact keyActions_names s _ _
  | insertText str rep => exact textActions_names s str rep
  | _ => first | exact names_nil _ | exact onField_names s _

/-- Nothing delivered means the app state is the one it started from. -/
def Untouched (a0 : S) (c : Ctx S) : Prop := c.delivered = false → c.app = a0

theorem give_untouched (app : App S) (a0 : S) (c : Ctx S) (m : Msg) :
    Untouched a0 (give app c m) := by
  intro h; simp [give] at h

theorem hear_untouched (app : App S) {a0 : S} {c : Ctx S} (h : Untouched a0 c) :
    Untouched a0 (hear app c) := by
  unfold hear; split
  · exact h
  · exact give_untouched app a0 _ _

theorem fire_untouched (app : App S) {a0 : S} {c : Ctx S} (n : String) (h : Untouched a0 c) :
    Untouched a0 (fire app c n) := by
  unfold fire; split
  · exact give_untouched app a0 _ _
  · exact h

theorem foldl_fire_untouched (app : App S) {a0 : S} (ns : List String) :
    ∀ {c : Ctx S}, Untouched a0 c → Untouched a0 (ns.foldl (fire app) c) := by
  induction ns with
  | nil => intro c h; exact h
  | cons n ns ih => intro c h; exact ih (fire_untouched app n h)

theorem boot_untouched (app : App S) {a0 : S} {c : Ctx S} (h : Untouched a0 c) :
    Untouched a0 (boot app c) := by
  unfold boot; split
  · exact h
  · intro h'; simp at h'

theorem admit_untouched (app : App S) (s : State S) (e : Event) :
    Untouched s.app (admit app s e) := by
  have base : Untouched s.app ({ app := s.app, world := s.world } : Ctx S) := fun _ => rfl
  cases e <;> simp only [admit] <;> (try exact base)
  case clock t =>
    have hb := boot_untouched app (c := { app := s.app, world := s.world.tick t }) (fun _ => rfl)
    split
    · exact hb
    · exact foldl_fire_untouched app _ (hear_untouched app hb)
  all_goals (split <;> (try split) <;>
    first | exact base | exact give_untouched app _ _ _ | exact hear_untouched app base)

theorem admit_input (app : App S) (s : State S) {e : Event} (h : e.isWorld = false) :
    admit app s e = { app := s.app, world := s.world } := by
  cases e <;> simp_all [Event.isWorld, admit]

/-- `step` passes `update` exactly the routed actions, in order, after telling the app the
time if it hasn't heard it: the app state after a step is `act` over `(route cfg.metrics s e).2`
from what the world events delivered. -/
theorem step_app (app : App S) (cfg : Config) (s : State S) (e : Event) :
    (step app cfg s e).1.app = (act app (admit app s e) (route cfg.metrics s e).2).app := by
  have hl := (route_laid cfg.metrics s e).2
  have hu := admit_untouched app s e
  unfold step
  generalize route cfg.metrics s e = r at hl ⊢
  obtain ⟨s1, acts⟩ := r
  dsimp only at hl ⊢
  split
  · rename_i hc
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true, List.isEmpty_iff] at hc
    obtain ⟨⟨ha, hd⟩, -⟩ := hc
    subst ha
    simp only [act, List.isEmpty_nil, ↓reduceIte]
    rw [hl, hu hd]
  · rfl

/-- For input events (not from the world), when the app has heard the current time, the app
state after a step is `update` folded over exactly the routed actions: M1's statement. -/
theorem step_delivers (app : App S) (cfg : Config) (s : State S) (e : Event)
    (hw : e.isWorld = false) (hh : s.world.heard = some s.world.clock) :
    (step app cfg s e).1.app = (deliver app.update s.app (route cfg.metrics s e).2).1 := by
  rw [step_app, admit_input app s hw]
  unfold act
  split
  · rename_i he
    simp only [List.isEmpty_iff] at he
    simp [he, deliver]
  · simp only [hear, hh, ↓reduceIte]

/-- An app that ignores the world: `receive` never changes its state (the default, and every M1
app's). -/
def Quiet (app : App S) : Prop := ∀ st m, (app.receive st m).1 = st

theorem give_app {app : App S} (h : Quiet app) (c : Ctx S) (m : Msg) : (give app c m).app = c.app :=
  h c.app m

theorem hear_app {app : App S} (h : Quiet app) (c : Ctx S) : (hear app c).app = c.app := by
  unfold hear; split
  · rfl
  · exact give_app h _ _

theorem fire_app {app : App S} (h : Quiet app) (c : Ctx S) (n : String) :
    (fire app c n).app = c.app := by
  unfold fire; split
  · exact give_app h _ _
  · rfl

theorem foldl_fire_app {app : App S} (h : Quiet app) (ns : List String) :
    ∀ (c : Ctx S), (ns.foldl (fire app) c).app = c.app := by
  induction ns with
  | nil => intro c; rfl
  | cons n ns ih => intro c; simp only [List.foldl_cons]; rw [ih, fire_app h]

theorem boot_app {app : App S} (h : Quiet app) (c : Ctx S) : (boot app c).app = c.app := by
  unfold boot; split
  · rfl
  · exact hear_app h _

theorem admit_app {app : App S} (h : Quiet app) (s : State S) (e : Event) :
    (admit app s e).app = s.app := by
  cases e <;> simp only [admit]
  case clock t =>
    split
    · exact boot_app h _
    · rw [foldl_fire_app h, hear_app h, boot_app h]
  all_goals (try split) <;> (try split) <;> (try rfl) <;>
    first | (rw [give_app h, hear_app h]) | exact hear_app h _

theorem act_app {app : App S} (h : Quiet app) (c : Ctx S) (acts : List Action) :
    (act app c acts).app = (deliver app.update c.app acts).1 := by
  unfold act; split
  · rename_i he
    simp only [List.isEmpty_iff] at he
    simp [he, deliver]
  · simp only [hear_app h]

/-! ### Any app: a step is a sequence of updates and messages -/

/-- One input to an app: an action to `update` or a message to `receive`. -/
def feed (app : App S) (st : S) : Action ⊕ Msg → S
  | .inl a => (app.update st a).1
  | .inr m => (app.receive st m).1

/-- `b` is `a` after some actions and messages. -/
def Fed (app : App S) (a b : S) : Prop := ∃ xs : List (Action ⊕ Msg), b = xs.foldl (feed app) a

theorem Fed.refl (app : App S) (a : S) : Fed app a a := ⟨[], rfl⟩

theorem Fed.trans {app : App S} {a b c : S} (h1 : Fed app a b) (h2 : Fed app b c) : Fed app a c := by
  obtain ⟨xs, rfl⟩ := h1; obtain ⟨ys, rfl⟩ := h2
  exact ⟨xs ++ ys, by rw [List.foldl_append]⟩

theorem give_fed (app : App S) (c : Ctx S) (m : Msg) : Fed app c.app (give app c m).app :=
  ⟨[.inr m], rfl⟩

theorem hear_fed (app : App S) (c : Ctx S) : Fed app c.app (hear app c).app := by
  unfold hear; split
  · exact Fed.refl _ _
  · exact give_fed _ _ _

theorem fire_fed (app : App S) (c : Ctx S) (n : String) : Fed app c.app (fire app c n).app := by
  unfold fire; split
  · exact give_fed _ _ _
  · exact Fed.refl _ _

theorem foldl_fire_fed (app : App S) (ns : List String) :
    ∀ (c : Ctx S), Fed app c.app (ns.foldl (fire app) c).app := by
  induction ns with
  | nil => intro c; exact Fed.refl _ _
  | cons n ns ih => intro c; exact (fire_fed app c n).trans (ih _)

theorem boot_fed (app : App S) (c : Ctx S) : Fed app c.app (boot app c).app := by
  unfold boot; split
  · exact Fed.refl _ _
  · exact hear_fed app _

theorem admit_fed (app : App S) (s : State S) (e : Event) : Fed app s.app (admit app s e).app := by
  cases e <;> simp only [admit] <;> (try exact Fed.refl _ _)
  case clock t =>
    split
    · exact boot_fed app _
    · exact ((boot_fed app _).trans (hear_fed app _)).trans (foldl_fire_fed app _ _)
  all_goals (try split) <;> (try split) <;> (try exact Fed.refl _ _) <;>
    first
    | exact (hear_fed app _).trans (give_fed app _ _)
    | exact hear_fed app _

theorem deliver_fed (u : S → Action → S × List Effect) (acts : List Action) :
    ∀ (st : S) (effs : List Effect),
      (acts.foldl (fun (p : S × List Effect) a => let (st', e) := u p.1 a; (st', p.2 ++ e))
        (st, effs)).1 = acts.foldl (fun s a => (u s a).1) st := by
  induction acts with
  | nil => intro st effs; rfl
  | cons a as ih => intro st effs; simp only [List.foldl_cons]; exact ih _ _

theorem foldl_feed_inl (app : App S) (acts : List Action) :
    ∀ (st : S), acts.foldl (fun s a => (app.update s a).1) st = (acts.map .inl).foldl (feed app) st := by
  induction acts with
  | nil => intro st; rfl
  | cons a as ih => intro st; simp only [List.foldl_cons, List.map_cons]; exact ih _

theorem act_fed (app : App S) (c : Ctx S) (acts : List Action) :
    Fed app c.app (act app c acts).app := by
  unfold act; split
  · exact Fed.refl _ _
  · refine (hear_fed app c).trans ⟨acts.map .inl, ?_⟩
    show (deliver app.update _ acts).1 = _
    unfold deliver
    rw [deliver_fed, foldl_feed_inl]

/-- **Any app.** The app state after a step is the one before after some updates and messages
(the routed actions, the clock, due timers, a reply or a subscription event). -/
theorem step_fed (app : App S) (cfg : Config) (s : State S) (e : Event) :
    Fed app s.app (step app cfg s e).1.app := by
  rw [step_app]
  exact (admit_fed app s e).trans (act_fed app _ _)

/-- For an app that ignores the world, the app state after any step is `update` folded over
exactly the routed actions. -/
theorem step_delivers_quiet {app : App S} (h : Quiet app) (cfg : Config) (s : State S)
    (e : Event) :
    (step app cfg s e).1.app = (deliver app.update s.app (route cfg.metrics s e).2).1 := by
  rw [step_app, act_app h, admit_app h]

/-! ## Pressable -/

/-- A focus request changes only the focus. -/
theorem applyFocus_pressed (effs : List Effect) (ui : UI) :
    (applyFocus effs ui).pressed = ui.pressed := by
  unfold applyFocus; split <;> rfl

/-- After a pointerDown on a non-field control `t`, the press is recorded on `t` with the
down's click count, whatever the update and relayout did, provided `t`'s ref is still in the
new tree. -/
theorem step_down_pressed (app : App S) (cfg : Config) (s : State S) (t : Target) (p : Point)
    (clicks : Nat) (mods : Mods) (hhit : hitTarget s.laid p = some t) (hf : t.isField = false)
    (hpres : t.ref ∈ refs (step app cfg s (.pointerDown p .primary clicks mods)).1.laid) :
    (step app cfg s (.pointerDown p .primary clicks mods)).1.ui.pressed = some t.ref ∧
    (step app cfg s (.pointerDown p .primary clicks mods)).1.clicks = clicks := by
  have hr : (route cfg.metrics s (.pointerDown p .primary clicks mods)).1.ui.pressed = some t.ref ∧
      (route cfg.metrics s (.pointerDown p .primary clicks mods)).1.clicks = clicks := by
    simp [route, hhit, hf, withPointer]
  revert hpres
  unfold step
  split
  rename_i s1 acts heq
  rw [heq] at hr
  dsimp only
  split
  · intro _; exact hr
  · intro hpres
    generalize act app (admit app s _) acts = c at hpres ⊢
    obtain ⟨l, hl⟩ := settle_spec app cfg c.app s1.pointer (applyFocus c.effs s1.ui) settleFuel
      (applyFocus c.effs s1.ui)
    simp only [hl] at hpres ⊢
    refine ⟨?_, hr.2⟩
    simp only [fixUI, Option.filter_eq_some_iff, applyFocus_pressed]
    exact ⟨hr.1, by simpa [present] using hpres⟩

/-- The actions of a pointerDown on a non-field control: at most a blur of the field that
loses focus. No press happens on the way down. -/
theorem down_actions (m : TextMetrics) (s : State S) (t : Target) (p : Point) (clicks : Nat)
    (mods : Mods) (hhit : hitTarget s.laid p = some t) (hf : t.isField = false) :
    (route m s (.pointerDown p .primary clicks mods)).2 = leave s none := by
  simp [route, hhit, hf]

/-- **Pressable, step level.** If a pointer at `p` reaches non-field control `t`, and after
the pointerDown (and whatever update and relayout it caused) `p` still reaches a non-field
control with the same ref, then the pointerUp at `p` delivers exactly `press t.ref`, and the
pointerDown delivered nothing but blurs. -/
theorem click_presses (app : App S) (cfg : Config) (s : State S) (t : Target) (p : Point)
    (mods mods' : Mods) (h0 : Reaches s.laid t p) (hf : t.isField = false)
    (h1 : ∃ t1, Reaches (step app cfg s (.pointerDown p .primary 1 mods)).1.laid t1 p ∧
      t1.ref = t.ref ∧ t1.isField = false) :
    (∀ a ∈ (route cfg.metrics s (.pointerDown p .primary 1 mods)).2, ∃ c, a = .blur c) ∧
    (route cfg.metrics (step app cfg s (.pointerDown p .primary 1 mods)).1
      (.pointerUp p .primary mods')).2 = [.press t.ref] := by
  have hhit := hitTarget_of_reaches h0
  refine ⟨by rw [down_actions _ s t p 1 mods hhit hf]; exact leave_blurs s none, ?_⟩
  obtain ⟨t1, hr1, he, hf1⟩ := h1
  have hm := mem_refs (reaches_mem hr1)
  rw [he] at hm
  obtain ⟨hp, hc⟩ := step_down_pressed app cfg s t p 1 mods hhit hf hm
  simp [route, hp, hc, hitTarget_of_reaches hr1, he, hf1]

/-- **Pressable** at the centre: under `LayoutFacts`, a click at the centre of the control's
visible rect presses it. -/
theorem click_center_presses (app : App S) (cfg : Config) (s : State S) (t : Target)
    (mods mods' : Mods) (h0 : LayoutFacts s.laid t) (hf : t.isField = false)
    (h1 : ∃ t1, Reaches (step app cfg s (.pointerDown t.visible.center .primary 1 mods)).1.laid
      t1 t.visible.center ∧ t1.ref = t.ref ∧ t1.isField = false) :
    (∀ a ∈ (route cfg.metrics s (.pointerDown t.visible.center .primary 1 mods)).2,
      ∃ c, a = .blur c) ∧
    (route cfg.metrics (step app cfg s (.pointerDown t.visible.center .primary 1 mods)).1
      (.pointerUp t.visible.center .primary mods')).2 = [.press t.ref] :=
  click_presses app cfg s t _ mods mods' h0.reaches hf h1

/-! ## Menus (docs/surfaces.md, section 1)

The menu is a description, not a laid tree, so these are about `Shown.statusOf`: the status
item the runtime holds for a place, which `step` refreshes whenever something is delivered. -/

/-- **Menu actions name menu items.** Opening a status item's menu presses only its control;
a selection presses only an enabled item of the menu the runtime holds for it now; closing
presses nothing. -/
theorem menu_route_names (m : TextMetrics) (s : State S) :
    (∀ p, ∀ a ∈ (route m s (.menuOpen p)).2,
      ∃ it, Shown.statusOf p s.surfaces = some it ∧ a = .press it.control) ∧
    (∀ p r, ∀ a ∈ (route m s (.menuSelect p r)).2,
      ∃ it, Shown.statusOf p s.surfaces = some it ∧ r ∈ MenuItem.enabledRefs it.menu ∧
        a = .press r) ∧
    (∀ p, (route m s (.menuClose p)).2 = []) := by
  refine ⟨fun p a ha => ?_, fun p r a ha => ?_, fun p => rfl⟩
  · simp only [route] at ha
    split at ha
    · rename_i it hit
      simp only [List.mem_singleton] at ha
      exact ⟨it, hit, ha⟩
    · simp only [List.not_mem_nil] at ha
  · simp only [route] at ha
    split at ha
    · rename_i it hit
      split at ha
      · rename_i hr
        simp only [List.mem_singleton] at ha
        exact ⟨it, hit, hr, ha⟩
      · simp only [List.not_mem_nil] at ha
    · simp only [List.not_mem_nil] at ha

/-- **A menu selection presses its item.** If `r` is an enabled item of the status item's
current menu, choosing it delivers exactly `press r` (the menu's `click_presses`, with no
layout in between). -/
theorem menu_select_presses (m : TextMetrics) (s : State S) {p : ClaimId} {it : StatusItem}
    {r : ControlRef} (h : Shown.statusOf p s.surfaces = some it)
    (hr : r ∈ MenuItem.enabledRefs it.menu) :
    route m s (.menuSelect p r) = (s, [.press r]) := by
  simp only [route, h, hr, ite_true]

/-- Opening a shown status item's menu presses its control. -/
theorem menu_open_presses (m : TextMetrics) (s : State S) {p : ClaimId} {it : StatusItem}
    (h : Shown.statusOf p s.surfaces = some it) :
    route m s (.menuOpen p) = (s, [.press it.control]) := by
  simp only [route, h]

theorem UI.same_self (a : UI) : UI.same a a = true := by
  simp only [UI.same, decide_true, Bool.and_self]

/-- **A stale menu selection is ignored.** If the chosen ref is not an enabled item of the
menu the runtime holds now (the menu changed while it was open, the item was disabled, or the
status item is gone), the step changes nothing at all: same app state, same runtime state, no
effects. -/
theorem menu_select_stale (app : App S) (cfg : Config) (s : State S) {p : ClaimId}
    {r : ControlRef}
    (h : ∀ it, Shown.statusOf p s.surfaces = some it → r ∉ MenuItem.enabledRefs it.menu) :
    step app cfg s (.menuSelect p r) = (s, []) := by
  have hroute : route cfg.metrics s (.menuSelect p r) = (s, []) := by
    simp only [route]
    split
    · rename_i it hit
      simp only [h it hit, ite_false]
    · rfl
  simp only [step, hroute, admit, List.isEmpty_nil, Bool.not_false, UI.same_self,
    Bool.and_self, ite_true]

/-- A selection addressed to an item not in the menu is ignored (a special case of
`menu_select_stale`): nothing outside the description can be pressed through the menu. -/
theorem menu_select_absent (app : App S) (cfg : Config) (s : State S) {p : ClaimId}
    {r : ControlRef}
    (h : ∀ it, Shown.statusOf p s.surfaces = some it → r ∉ MenuItem.refs it.menu) :
    step app cfg s (.menuSelect p r) = (s, []) :=
  menu_select_stale app cfg s fun it hit hr => h it hit (MenuItem.mem_refs_of_enabled hr)

/-- Events addressed to a surface other than the window (a panel, a status item) do nothing. -/
theorem route_surface_other (m : TextMetrics) (s : State S) {p : ClaimId} (e : Event)
    (h : Shown.windowPlace s.surfaces ≠ some p) : route m s (.surface p e) = (s, []) := by
  simp only [route, h, decide_false, Bool.false_and, Bool.false_eq_true, ite_false]

/-! ## What the surfaces show follows the app state -/

theorem tab_surfaces (s : State S) (back : Bool) : (tab s back).1.surfaces = s.surfaces := by
  unfold tab; split <;> rfl

theorem route_surfaces (m : TextMetrics) (s : State S) (e : Event) :
    (route m s e).1.surfaces = s.surfaces := by
  induction e with
  | surface p e ih => simp only [route]; split; exact ih; rfl
  | _ =>
    rw [route.eq_def] <;> (try simp only [withPointer]) <;> (try split) <;> (try split) <;>
      (try split) <;> (try split) <;> first | contradiction | simp [tab_surfaces]

/-- A context that delivered nothing still holds the app state `a`. -/
def Kept (a : S) (c : Ctx S) : Prop := c.delivered = false → c.app = a

theorem give_kept (app : App S) (a : S) (c : Ctx S) (m : Msg) : Kept a (give app c m) :=
  fun h => nomatch h

theorem hear_kept (app : App S) (a : S) (c : Ctx S) (h : Kept a c) : Kept a (hear app c) := by
  unfold hear; split
  · exact h
  · exact give_kept app a _ _

theorem fire_kept (app : App S) (a : S) (c : Ctx S) (n : String) (h : Kept a c) :
    Kept a (fire app c n) := by
  unfold fire; split
  · exact give_kept app a _ _
  · exact h

theorem boot_kept (app : App S) (a : S) (c : Ctx S) (h : Kept a c) : Kept a (boot app c) := by
  unfold boot; split
  · exact h
  · intro hd; nomatch hd

theorem foldl_fire_kept (app : App S) (a : S) (ns : List String) :
    ∀ (c : Ctx S), Kept a c → Kept a (ns.foldl (fire app) c) := by
  induction ns with
  | nil => intro c h; exact h
  | cons n ns ih => intro c h; exact ih _ (fire_kept app a c n h)

/-- `admit` changes the app state only by delivering something. -/
theorem admit_kept (app : App S) (s : State S) (e : Event) : Kept s.app (admit app s e) := by
  unfold admit
  split
  · simp only
    split
    · exact boot_kept app _ _ (fun _ => rfl)
    · exact foldl_fire_kept app _ _ _ (hear_kept app _ _ (boot_kept app _ _ (fun _ => rfl)))
  · split
    · dsimp only
      split
      · exact give_kept app _ _ _
      · exact hear_kept app _ _ (fun _ => rfl)
    · exact fun _ => rfl
  · split
    · exact give_kept app _ _ _
    · exact fun _ => rfl
  · exact fun _ => rfl

/-- Each step keeps the runtime's surfaces equal to what the app's surfaces show for its state:
the menu `menuSelect` is checked against is the menu of the current app state. -/
theorem step_surfaces (app : App S) (cfg : Config) (s : State S) (e : Event)
    (h : s.surfaces = shows app cfg s.app) :
    (step app cfg s e).1.surfaces = shows app cfg (step app cfg s e).1.app := by
  have hr := route_surfaces cfg.metrics s e
  have ha := (route_laid cfg.metrics s e).2
  have hk := admit_kept app s e
  unfold step
  rcases hrt : route cfg.metrics s e with ⟨s1, acts⟩
  rw [hrt] at hr ha
  generalize admit app s e = c0 at hk
  dsimp only
  split
  · rename_i hc
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hc
    dsimp only
    rw [hr, ha, h]
  · generalize hca : act app c0 acts = c
    by_cases hd : c.delivered = true
    · simp only [hd, ↓reduceIte]
    · have hd' : c.delivered = false := by simpa only [Bool.not_eq_true] using hd
      simp only [hd', Bool.false_eq_true, ↓reduceIte]
      subst hca
      unfold act at hd' ⊢
      split at hd'
      · rename_i he
        simp only [he, ↓reduceIte]
        rw [show s1.surfaces = s.surfaces from hr, h, hk hd']
      · nomatch hd'

theorem start_surfaces (app : App S) (cfg : Config) (size : Size) (scale : Nat) :
    (start app cfg size scale).surfaces = shows app cfg (start app cfg size scale).app := rfl

/-- In every state the running app reaches, the surfaces show the current app state. -/
theorem steps_surfaces (app : App S) (cfg : Config) (es : List Event) :
    ∀ (s : State S), s.surfaces = shows app cfg s.app →
      (steps app cfg s es).1.surfaces = shows app cfg (steps app cfg s es).1.app := by
  unfold steps
  suffices ∀ (es : List Event) (acc : State S × List Effect), acc.1.surfaces = shows app cfg acc.1.app →
      (es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e')) acc).1.surfaces =
        shows app cfg (es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e')) acc).1.app
    from fun s h => this es (s, []) h
  intro es
  induction es with
  | nil => intro acc h; exact h
  | cons e es ih =>
    intro ⟨s, effs⟩ h
    exact ih _ (step_surfaces app cfg s e h)

end Cairn.Runtime
