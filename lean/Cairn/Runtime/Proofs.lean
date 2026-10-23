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
  cases e <;> simp only [route, withPointer] <;> (try split) <;> (try split) <;>
    (try split) <;> simp [tab_fst]

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
control of the laid tree on screen when the event arrived. (`step` delivers exactly
`(route cfg.metrics s e).2`.) -/
theorem route_names (m : TextMetrics) (s : State S) (e : Event) :
    Names s.laid (route m s e).2 := by
  cases e with
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
  all_goals (split <;> first | exact base | exact give_untouched app _ _ _)

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

theorem boot_app (app : App S) (c : Ctx S) : (boot app c).app = c.app := by
  unfold boot; split <;> rfl

theorem admit_app {app : App S} (h : Quiet app) (s : State S) (e : Event) :
    (admit app s e).app = s.app := by
  cases e <;> simp only [admit]
  case clock t =>
    split
    · exact boot_app _ _
    · rw [foldl_fire_app h, hear_app h, boot_app]
  all_goals (try split) <;> (try rfl) <;> (rw [give_app h, hear_app h])

theorem act_app {app : App S} (h : Quiet app) (c : Ctx S) (acts : List Action) :
    (act app c acts).app = (deliver app.update c.app acts).1 := by
  unfold act; split
  · rename_i he
    simp only [List.isEmpty_iff] at he
    simp [he, deliver]
  · simp only [hear_app h]

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

end Cairn.Runtime
