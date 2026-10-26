import Cairn.Runtime.Step

/-! Theorems about the runtime: actions name controls on screen, interaction state stays
sound, and a click at a reachable control presses it. -/

namespace Cairn.Runtime

variable {S : Type}

/-! ## Routing leaves the app and the tree alone -/

theorem tab_fst (s : State S) (back : Bool) :
    (tab s back).1.laid = s.laid ∧ (tab s back).1.app = s.app := by
  unfold tab; split <;> simp

/-- Scrolling changes only the `UI`. -/
theorem wheel_eq (s : State S) (p : Point) (dx dy : Int) : ∃ ui, wheel s p dx dy = { s with ui } := by
  unfold wheel; split
  · exact ⟨_, rfl⟩
  · exact ⟨s.ui, rfl⟩

theorem keyScrollState_eq (s : State S) (k : Key) (mods : Mods) :
    ∃ ui, keyScrollState s k mods = { s with ui } := by
  unfold keyScrollState
  split
  · split
    · split
      · exact ⟨_, rfl⟩
      · exact ⟨s.ui, rfl⟩
    · exact ⟨s.ui, rfl⟩
  · exact ⟨s.ui, rfl⟩

theorem wheel_fst (s : State S) (p : Point) (dx dy : Int) :
    (wheel s p dx dy).laid = s.laid ∧ (wheel s p dx dy).app = s.app ∧
      (wheel s p dx dy).surfaces = s.surfaces := by
  obtain ⟨ui, h⟩ := wheel_eq s p dx dy
  rw [h]; exact ⟨rfl, rfl, rfl⟩

theorem keyScrollState_fst (s : State S) (k : Key) (mods : Mods) :
    (keyScrollState s k mods).laid = s.laid ∧ (keyScrollState s k mods).app = s.app ∧
      (keyScrollState s k mods).surfaces = s.surfaces := by
  obtain ⟨ui, h⟩ := keyScrollState_eq s k mods
  rw [h]; exact ⟨rfl, rfl, rfl⟩

theorem openAt_fst (s : State S) (r : ControlRef) :
    (openAt s r).laid = s.laid ∧ (openAt s r).app = s.app ∧ (openAt s r).surfaces = s.surfaces :=
  ⟨rfl, rfl, rfl⟩

theorem secondaryDown_fst (s : State S) (p : Point) :
    (secondaryDown s p).laid = s.laid ∧ (secondaryDown s p).app = s.app ∧
      (secondaryDown s p).surfaces = s.surfaces := by
  unfold secondaryDown; split <;> exact ⟨rfl, rfl, rfl⟩

theorem keyRoute_fst (s : State S) (k : Key) (mods : Mods) :
    (keyRoute s k mods).1.laid = s.laid ∧ (keyRoute s k mods).1.app = s.app ∧
      (keyRoute s k mods).1.surfaces = s.surfaces := by
  unfold keyRoute; split
  · exact ⟨rfl, rfl, rfl⟩
  · exact keyScrollState_fst s k mods

theorem textRoute_fst (s : State S) (str : String) (rep : Option (Nat × Nat)) :
    (textRoute s str rep).1.laid = s.laid ∧ (textRoute s str rep).1.app = s.app ∧
      (textRoute s str rep).1.surfaces = s.surfaces := by
  unfold textRoute; split <;> exact ⟨rfl, rfl, rfl⟩

theorem route_laid (m : TextMetrics) (s : State S) (e : Event) :
    (route m s e).1.laid = s.laid ∧ (route m s e).1.app = s.app := by
  induction e with
  | surface p e ih => simp only [route]; split; exact ih; exact ⟨rfl, rfl⟩
  | _ =>
    rw [route.eq_def] <;> (try simp only [withPointer]) <;> (try split) <;> (try split) <;>
      (try split) <;> (try split) <;>
      first | contradiction | simp [tab_fst, wheel_fst, keyScrollState_fst, secondaryDown_fst, keyRoute_fst, textRoute_fst]

/-! ## Interaction state is sound -/

/-- Focus is a focusable control of the tree on screen; hover and press are controls of it. -/
def Sound (s : State S) : Prop :=
  (∀ r, s.ui.focus = some r → ∃ t ∈ targets s.laid, t.ref = r ∧ t.focusable = true) ∧
  (∀ r, s.ui.hover = some r → r ∈ refs s.laid) ∧
  (∀ r, s.ui.pressed = some r → r ∈ refs s.laid)

theorem fixUI_sound (laid : Laid) (pointer : Option Point) (ui : UI) (keep : List ControlRef) :
    (∀ r, (fixUI laid pointer ui keep).focus = some r →
      ∃ t ∈ targets laid, t.ref = r ∧ t.focusable = true) ∧
    (∀ r, (fixUI laid pointer ui keep).hover = some r → r ∈ refs laid) ∧
    (∀ r, (fixUI laid pointer ui keep).pressed = some r → r ∈ refs laid) := by
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
    ∀ fuel ui, ∃ l, settle app cfg st pointer ui0 fuel ui = (fixUI l pointer ui0 (app.keepScroll st), l)
  | 0, ui => ⟨relayout app cfg st ui, rfl⟩
  | f + 1, ui => by
    simp only [settle]
    split
    · exact ⟨_, rfl⟩
    · exact settle_spec app cfg st pointer ui0 f _

/-- What `aim` returns is still a `UI` repaired against the tree returned with it, from one with
`ui1`'s focus and press. -/
theorem aim_spec (app : App S) (cfg : Config) (st : S) (pointer : Option Point) (ui1 : UI)
    (goals : List (ControlRef × ScrollTarget)) :
    ∀ fuel x, (∃ l u, x = (fixUI l pointer u (app.keepScroll st), l) ∧ u.focus = ui1.focus ∧
        u.pressed = ui1.pressed) →
      ∃ l u, aim app cfg st pointer ui1 goals fuel x = (fixUI l pointer u (app.keepScroll st), l) ∧
        u.focus = ui1.focus ∧ u.pressed = ui1.pressed
  | 0, _, h => h
  | f + 1, (ui, laid), h => by
    simp only [aim]
    split
    · exact h
    · apply aim_spec
      obtain ⟨l, hl⟩ := settle_spec app cfg st pointer _ settleFuel (aimScroll goals laid ui)
      exact ⟨l, _, hl, rfl, rfl⟩

/-- `lay` returns a `UI` repaired against the tree returned with it, from one with `ui1`'s focus
and press (`ui1` itself, unless a scroll request moved an offset). -/
theorem lay_spec (app : App S) (cfg : Config) (st : S) (pointer : Option Point)
    (goals : List (ControlRef × ScrollTarget)) (ui1 : UI) :
    ∃ l u, lay app cfg st pointer goals ui1 = (fixUI l pointer u (app.keepScroll st), l) ∧
      u.focus = ui1.focus ∧ u.pressed = ui1.pressed := by
  obtain ⟨l, hl⟩ := settle_spec app cfg st pointer ui1 settleFuel ui1
  have h0 : ∃ l u, settle app cfg st pointer ui1 settleFuel ui1 =
      (fixUI l pointer u (app.keepScroll st), l) ∧ u.focus = ui1.focus ∧ u.pressed = ui1.pressed :=
    ⟨l, ui1, hl, rfl, rfl⟩
  unfold lay
  split
  · exact h0
  · exact aim_spec app cfg st pointer ui1 goals aimFuel _ h0

theorem sound_settle (app : App S) (cfg : Config) (st : S) (pointer : Option Point) (ui0 : UI)
    (fuel : Nat) (ui : UI) (s : State S)
    (h : (s.ui, s.laid) = settle app cfg st pointer ui0 fuel ui) : Sound s := by
  obtain ⟨l, hl⟩ := settle_spec app cfg st pointer ui0 fuel ui
  rw [hl] at h
  simp only [Prod.mk.injEq] at h
  obtain ⟨h1, h2⟩ := h
  unfold Sound; rw [h1, h2]; exact fixUI_sound l pointer ui0 _

theorem sound_lay (app : App S) (cfg : Config) (st : S) (pointer : Option Point)
    (goals : List (ControlRef × ScrollTarget)) (ui1 : UI) (s : State S)
    (h : (s.ui, s.laid) = lay app cfg st pointer goals ui1) : Sound s := by
  obtain ⟨l, u, hl, -, -⟩ := lay_spec app cfg st pointer goals ui1
  rw [hl] at h
  simp only [Prod.mk.injEq] at h
  obtain ⟨h1, h2⟩ := h
  unfold Sound; rw [h1, h2]; exact fixUI_sound l pointer u _

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
    · exact sound_lay app cfg _ _ _ _ _ rfl

theorem steps_sound (app : App S) (cfg : Config) (s : State S) (es : List Event)
    (h : Sound s) : Sound (steps app cfg s es).1 := by
  unfold steps
  suffices ∀ (es : List Event) (acc : State S × List Effect), Sound acc.1 →
      Sound (es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e')) acc).1 from
    this (es ++ frameEvents) (s, []) h
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

theorem keyRoute_names (s : State S) (k : Key) (mods : Mods) :
    Names s.laid (keyRoute s k mods).2 := by
  unfold keyRoute; split
  · exact names_nil _
  · exact keyActions_names s k mods

theorem textRoute_names (s : State S) (str : String) (rep : Option (Nat × Nat)) :
    Names s.laid (textRoute s str rep).2 := by
  unfold textRoute; split
  · exact names_nil _
  · exact textActions_names s str rep

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

theorem mem_appearRefs {laid : Laid} {r : ControlRef} :
    r ∈ appearRefs laid ↔
      ∃ t ∈ targets laid, t.control.appear = true ∧ t.visible.nonempty ∧ t.ref = r := by
  unfold appearRefs
  simp only [List.mem_filterMap]
  constructor
  · rintro ⟨t, ht, h⟩
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
      simp only [Option.some.injEq] at h
      exact ⟨t, ht, hc.1, hc.2, h⟩
    · simp at h
  · rintro ⟨t, ht, ha, hv, rfl⟩
    exact ⟨t, ht, by simp [ha, hv]⟩

/-- **Appear, exactly.** The frame event delivers `appear c` exactly when `c` is a control of the
tree on screen marked `appear` with a visible part, and isn't among the controls seen at the last
frame. -/
theorem mem_appearing {laid : Laid} {seen : List ControlRef} {a : Action} :
    a ∈ appearing laid seen ↔
      ∃ c, a = .appear c ∧ c ∉ seen ∧
        ∃ t ∈ targets laid, t.control.appear = true ∧ t.visible.nonempty ∧ t.ref = c := by
  unfold appearing
  simp only [List.mem_map, List.mem_filter, Bool.not_eq_eq_eq_not, Bool.not_true,
    List.contains_eq_mem, decide_eq_false_iff_not]
  constructor
  · rintro ⟨c, ⟨hc, hs⟩, rfl⟩
    exact ⟨c, rfl, hs, mem_appearRefs.mp hc⟩
  · rintro ⟨c, rfl, hs, h⟩
    exact ⟨c, ⟨mem_appearRefs.mpr h, hs⟩, rfl⟩

theorem appearing_names (laid : Laid) (seen : List ControlRef) :
    Names laid (appearing laid seen) := by
  intro a ha
  obtain ⟨c, rfl, -, t, ht, -, -, rfl⟩ := mem_appearing.mp ha
  exact mem_refs ht

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
        · exact names_nil _
        · split
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
      first | exact tab_names s _ | exact keyRoute_names s _ _
  | insertText str rep => exact textRoute_names s str rep
  | frame => exact appearing_names s.laid s.seen
  | _ => first | exact names_nil _ | exact onField_names s _

/-! ### Releasing a slot touches neither the app nor what was delivered -/

@[simp] theorem release_app (c : Ctx S) (w : World) : (release c w).app = c.app := rfl
@[simp] theorem release_delivered (c : Ctx S) (w : World) : (release c w).delivered = c.delivered := rfl

@[simp] theorem ack_app (c : Ctx S) (id : Nat) : (ack c id).app = c.app := by
  unfold ack; split <;> rfl
@[simp] theorem ack_delivered (c : Ctx S) (id : Nat) : (ack c id).delivered = c.delivered := by
  unfold ack; split <;> rfl

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
  case reply id r =>
    split
    · split
      · exact give_untouched app _ _ _
      · intro hd; rw [ack_delivered] at hd; rw [ack_app]; exact hear_untouched app base hd
    · intro _; rw [ack_app]
  case subEvent id ev =>
    split
    · exact give_untouched app _ _ _
    · exact base

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
  case reply id r =>
    split
    · split
      · rw [give_app h, release_app, hear_app h]
      · rw [ack_app, hear_app h]
    · exact ack_app _ _
  case subEvent id ev =>
    split
    · rw [give_app h, hear_app h]
    · rfl
  all_goals rfl

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
  case reply id r =>
    split
    · split
      · exact (hear_fed app _).trans (give_fed app (release _ _) _)
      · rw [ack_app]; exact hear_fed app _
    · rw [ack_app]; exact Fed.refl _ _
  case subEvent id ev =>
    split
    · exact (hear_fed app _).trans (give_fed app _ _)
    · exact Fed.refl _ _

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
    (hb : t.menuButton = false)
    (hpres : t.ref ∈ refs (step app cfg s (.pointerDown p .primary clicks mods)).1.laid) :
    (step app cfg s (.pointerDown p .primary clicks mods)).1.ui.pressed = some t.ref ∧
    (step app cfg s (.pointerDown p .primary clicks mods)).1.clicks = clicks := by
  have hr : (route cfg.metrics s (.pointerDown p .primary clicks mods)).1.ui.pressed = some t.ref ∧
      (route cfg.metrics s (.pointerDown p .primary clicks mods)).1.clicks = clicks := by
    simp [route, hhit, hf, hb, withPointer]
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
    obtain ⟨l, u, hl, -, hp⟩ := lay_spec app cfg c.app s1.pointer (requestedScrolls c.effs)
      (applyFocus c.effs s1.ui)
    simp only [hl] at hpres ⊢
    refine ⟨?_, hr.2⟩
    simp only [fixUI, Option.filter_eq_some_iff, hp, applyFocus_pressed]
    exact ⟨hr.1, by simpa [present] using hpres⟩

/-- The actions of a pointerDown on a non-field control that isn't a menu button: at most a
blur of the field that loses focus. No press happens on the way down. -/
theorem down_actions (m : TextMetrics) (s : State S) (t : Target) (p : Point) (clicks : Nat)
    (mods : Mods) (hhit : hitTarget s.laid p = some t) (hf : t.isField = false)
    (hb : t.menuButton = false) :
    (route m s (.pointerDown p .primary clicks mods)).2 = leave s none := by
  simp [route, hhit, hf, hb]

/-- **Pressable, step level.** If a pointer at `p` reaches non-field control `t` that isn't a
menu button (a menu button's click opens its menu instead), and after
the pointerDown (and whatever update and relayout it caused) `p` still reaches a non-field
control with the same ref, then the pointerUp at `p` delivers exactly `press t.ref`, and the
pointerDown delivered nothing but blurs. -/
theorem click_presses (app : App S) (cfg : Config) (s : State S) (t : Target) (p : Point)
    (mods mods' : Mods) (h0 : Reaches s.laid t p) (hf : t.isField = false)
    (hb : t.menuButton = false)
    (h1 : ∃ t1, Reaches (step app cfg s (.pointerDown p .primary 1 mods)).1.laid t1 p ∧
      t1.ref = t.ref ∧ t1.isField = false) :
    (∀ a ∈ (route cfg.metrics s (.pointerDown p .primary 1 mods)).2, ∃ c, a = .blur c) ∧
    (route cfg.metrics (step app cfg s (.pointerDown p .primary 1 mods)).1
      (.pointerUp p .primary mods')).2 = [.press t.ref] := by
  have hhit := hitTarget_of_reaches h0
  refine ⟨by rw [down_actions _ s t p 1 mods hhit hf hb]; exact leave_blurs s none, ?_⟩
  obtain ⟨t1, hr1, he, hf1⟩ := h1
  have hm := mem_refs (reaches_mem hr1)
  rw [he] at hm
  obtain ⟨hp, hc⟩ := step_down_pressed app cfg s t p 1 mods hhit hf hb hm
  simp [route, hp, hc, hitTarget_of_reaches hr1, he, hf1]

/-- **Pressable** at the centre: under `LayoutFacts`, a click at the centre of the control's
visible rect presses it. -/
theorem click_center_presses (app : App S) (cfg : Config) (s : State S) (t : Target)
    (mods mods' : Mods) (h0 : LayoutFacts s.laid t) (hf : t.isField = false)
    (hb : t.menuButton = false)
    (h1 : ∃ t1, Reaches (step app cfg s (.pointerDown t.visible.center .primary 1 mods)).1.laid
      t1 t.visible.center ∧ t1.ref = t.ref ∧ t1.isField = false) :
    (∀ a ∈ (route cfg.metrics s (.pointerDown t.visible.center .primary 1 mods)).2,
      ∃ c, a = .blur c) ∧
    (route cfg.metrics (step app cfg s (.pointerDown t.visible.center .primary 1 mods)).1
      (.pointerUp t.visible.center .primary mods')).2 = [.press t.ref] :=
  click_presses app cfg s t _ mods mods' h0.reaches hf hb h1

/-! ## Menus (docs/surfaces.md, section 1, "Menus on controls" and "The app's menus")

A menu is a description, not a laid tree. A selection is checked against `selectMenu`: for the
window's place, the control menu open now (`openMenu`: `UI.menu`'s control's menu in the tree
on screen); for another place, a status item's menu or the menu bar's items, which `step`
refreshes whenever something is delivered (`step_surfaces`). -/

/-- **Menu actions name menu items.** Opening a status item's menu presses only its control;
a selection presses only an enabled item of the menu it is checked against now; closing
presses nothing. -/
theorem menu_route_names (m : TextMetrics) (s : State S) :
    (∀ p, ∀ a ∈ (route m s (.menuOpen p)).2,
      ∃ it, Shown.statusOf p s.surfaces = some it ∧ a = .press it.control) ∧
    (∀ p r, ∀ a ∈ (route m s (.menuSelect p r)).2,
      ∃ ms, selectMenu s p = some ms ∧ r ∈ MenuItem.enabledRefs ms ∧ a = .press r) ∧
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
    · rename_i ms hms
      split at ha
      · rename_i hr
        simp only [List.mem_singleton] at ha
        exact ⟨ms, hms, hr, ha⟩
      · simp only [List.not_mem_nil] at ha
    · simp only [List.not_mem_nil] at ha

/-- For the window's place, a selection is checked against the control menu open now. -/
theorem selectMenu_window {s : State S} {p : ClaimId} (h : Shown.windowPlace s.surfaces = some p) :
    selectMenu s p = (openMenu s).map (·.2.items) := by
  simp only [selectMenu, h, ite_true]

/-- **A control menu's choice is an item of the menu open now.** Every action a selection
addressed to the window delivers is a press of an enabled item of the control menu open now
(`openMenu`: `UI.menu`'s control, its menu in the tree on screen); with no menu open, or an item
that isn't an enabled item of it, nothing. -/
theorem control_menu_select_names (m : TextMetrics) (s : State S) {p : ClaimId} {r : ControlRef}
    (hw : Shown.windowPlace s.surfaces = some p) :
    ∀ a ∈ (route m s (.menuSelect p r)).2,
      ∃ o cm, openMenu s = some (o, cm) ∧ r ∈ MenuItem.enabledRefs cm.items ∧ a = .press r := by
  intro a ha
  obtain ⟨ms, hms, hr, rfl⟩ := (menu_route_names m s).2.1 p r a ha
  rw [selectMenu_window hw] at hms
  obtain ⟨⟨o, cm⟩, ho, rfl⟩ := Option.map_eq_some_iff.mp hms
  exact ⟨o, cm, ho, hr, rfl⟩

/-- **A menu selection presses its item.** If `r` is an enabled item of the menu a selection
for `p` is checked against, choosing it delivers exactly `press r` (the menu's `click_presses`,
with no layout in between). -/
theorem menu_select_presses (m : TextMetrics) (s : State S) {p : ClaimId} {ms : List MenuItem}
    {r : ControlRef} (h : selectMenu s p = some ms) (hr : r ∈ MenuItem.enabledRefs ms) :
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
menu the selection is checked against now (the menu changed while it was open, the item was
disabled, the status item or the control is gone, or no control menu is open), the step changes
nothing at all: same app state, same runtime state, no effects. -/
theorem menu_select_stale (app : App S) (cfg : Config) (s : State S) {p : ClaimId}
    {r : ControlRef}
    (h : ∀ ms, selectMenu s p = some ms → r ∉ MenuItem.enabledRefs ms) :
    step app cfg s (.menuSelect p r) = (s, []) := by
  have hroute : route cfg.metrics s (.menuSelect p r) = (s, []) := by
    simp only [route]
    split
    · rename_i ms hms
      simp only [h ms hms, ite_false]
    · rfl
  simp only [step, hroute, admit, List.isEmpty_nil, Bool.not_false, UI.same_self,
    Bool.and_self, ite_true]

/-- A selection addressed to an item not in the menu is ignored (a special case of
`menu_select_stale`): nothing outside the description can be pressed through the menu. -/
theorem menu_select_absent (app : App S) (cfg : Config) (s : State S) {p : ClaimId}
    {r : ControlRef}
    (h : ∀ ms, selectMenu s p = some ms → r ∉ MenuItem.refs ms) :
    step app cfg s (.menuSelect p r) = (s, []) :=
  menu_select_stale app cfg s fun ms hms hr => h ms hms (MenuItem.mem_refs_of_enabled hr)

/-! ### Opening a control menu -/

mutual
theorem menuHitsOf_owner (o : Option Target) : ∀ (l : Laid) (h : Hit), h ∈ menuHitsOf o l →
    h.owner = o ∨ ∃ t ∈ targetsOf l, h.owner = some t ∧ t.node.menu?.isSome = true
  | n@(.box r cl st c cs), h, hm => by
    cases c with
    | none =>
      simp only [menuHitsOf, targetsOf, List.mem_append, List.nil_append] at hm ⊢
      rcases hm with hm | hm
      · split at hm <;> simp_all
      · exact menuHitsList_owner o cs h hm
    | some k =>
      simp only [menuHitsOf, targetsOf, List.mem_append, List.singleton_append] at hm ⊢
      by_cases hk : (Laid.box r cl st (some k) cs).menu?.isSome = true
      · simp only [hk, ite_true] at hm
        right
        rcases hm with hm | hm
        · split at hm
          · simp only [List.mem_singleton] at hm; subst hm
            exact ⟨_, List.mem_cons_self, rfl, hk⟩
          · simp at hm
        · rcases menuHitsList_owner _ cs h hm with e | ⟨t, ht, e, he⟩
          · exact ⟨_, List.mem_cons_self, e, hk⟩
          · exact ⟨t, List.mem_cons_of_mem _ ht, e, he⟩
      · simp only [hk, Bool.false_eq_true, ite_false] at hm
        rcases hm with hm | hm
        · split at hm
          · simp only [List.mem_singleton] at hm; subst hm; exact .inl rfl
          · simp at hm
        · rcases menuHitsList_owner _ cs h hm with e | ⟨t, ht, e, he⟩
          · exact .inl e
          · exact .inr ⟨t, List.mem_cons_of_mem _ ht, e, he⟩
  | .text .., h, hm => by simp_all [menuHitsOf]
  | n@(.field r cl st ts c v o ca sel), h, hm => by
    simp only [menuHitsOf, List.mem_singleton] at hm
    subst hm
    by_cases hk : (Laid.field r cl st ts c v o ca sel).menu?.isSome = true
    · simp only [hk, ite_true, targetsOf, List.mem_singleton]
      exact .inr ⟨_, rfl, rfl, hk⟩
    · simp only [hk, Bool.false_eq_true, ite_false]; simp
theorem menuHitsList_owner (o : Option Target) : ∀ (ls : List Laid) (h : Hit),
    h ∈ menuHitsList o ls →
    h.owner = o ∨ ∃ t ∈ targetsList ls, h.owner = some t ∧ t.node.menu?.isSome = true
  | [], h, hm => by simp [menuHitsList] at hm
  | l :: ls, h, hm => by
    simp only [menuHitsList, targetsList, List.mem_append] at hm ⊢
    rcases hm with hm | hm
    · rcases menuHitsOf_owner o l h hm with e | ⟨t, ht, e, he⟩
      · exact .inl e
      · exact .inr ⟨t, .inl ht, e, he⟩
    · rcases menuHitsList_owner o ls h hm with e | ⟨t, ht, e, he⟩
      · exact .inl e
      · exact .inr ⟨t, .inr ht, e, he⟩
end

/-- The control a secondary click opens is a control of the tree that has a menu. -/
theorem menuTarget_mem {laid : Laid} {p : Point} {t : Target} (h : menuTarget laid p = some t) :
    t ∈ targets laid ∧ t.node.menu?.isSome = true := by
  unfold menuTarget at h
  cases hf : (menuHitsOf none laid).reverse.find? (·.visible.contains p) with
  | none => simp [hf] at h
  | some e =>
    simp only [hf, Option.bind_some] at h
    rcases menuHitsOf_owner none laid e (List.mem_reverse.mp (List.mem_of_find?_eq_some hf))
      with he | ⟨t', ht', he, hm⟩
    · rw [h] at he; cases he
    · rw [h] at he; cases he; exact ⟨ht', hm⟩

/-- **A secondary click on a control without a menu changes nothing but hover**: with no
control with a menu at or above the point, the runtime moves the pointer (and so hover) and
delivers nothing, as before menus on controls. -/
theorem secondary_no_menu (m : TextMetrics) (s : State S) {p : Point} (clicks : Nat) (mods : Mods)
    (h : menuTarget s.laid p = none) :
    route m s (.pointerDown p .secondary clicks mods) = (withPointer s p, []) := by
  simp only [route, secondaryDown, h]

/-- A secondary click on a control with a menu (or inside one) opens that menu and delivers
nothing. -/
theorem secondary_opens (m : TextMetrics) (s : State S) {p : Point} {t : Target} (clicks : Nat)
    (mods : Mods) (h : menuTarget s.laid p = some t) :
    route m s (.pointerDown p .secondary clicks mods) = (openAt (withPointer s p) t.ref, []) := by
  simp only [route, secondaryDown, h]

theorem setScroll_menu (ui : UI) (r : ControlRef) (o : Int) : (ui.setScroll r o).menu = ui.menu := by
  unfold UI.setScroll; split <;> rfl

theorem revealIn_menu (chain : List Scroller) (ui : UI) (q : Rect) :
    (revealIn chain ui q).menu = ui.menu := by
  unfold revealIn
  suffices ∀ (chain : List Scroller), (chain.foldr (fun sc (acc : UI × Rect) =>
      let (ui, q) := acc
      let cur := ui.scrollOf sc.ref
      let o := revealOff sc cur q
      let d := o - cur
      (ui.setScroll sc.ref o,
       if sc.horiz then { q with x := q.x - d } else { q with y := q.y - d })) (ui, q)).1.menu =
        ui.menu from this chain
  intro chain
  induction chain with
  | nil => rfl
  | cons sc cs ih => simp only [List.foldr_cons, setScroll_menu]; exact ih

theorem tab_menu (s : State S) (back : Bool) : (tab s back).1.ui.menu = s.ui.menu := by
  unfold tab; split
  · rfl
  · simp only [revealIn_menu]

theorem wheel_menu (s : State S) (p : Point) (dx dy : Int) :
    (wheel s p dx dy).ui.menu = s.ui.menu := by
  unfold wheel; split
  · simp only [UI.scrollTo, setScroll_menu]
  · rfl

theorem keyScrollState_menu (s : State S) (k : Key) (mods : Mods) :
    (keyScrollState s k mods).ui.menu = s.ui.menu := by
  unfold keyScrollState
  split
  · split
    · split
      · simp only [UI.scrollTo, setScroll_menu]
      · rfl
    · rfl
  · rfl

/-- **Opening a menu reaches no update.** Whenever routing an event opens a control menu (the
menu open after it is one that wasn't open before: a secondary click, a menu button's primary
click, Space or Return on a focused menu button, the context-menu key), it delivers no action. -/
theorem route_open_quiet (m : TextMetrics) (s : State S) (e : Event) {r : ControlRef}
    (h : (route m s e).1.ui.menu = some r) (hne : s.ui.menu ≠ some r) : (route m s e).2 = [] := by
  induction e with
  | surface p e ih =>
    simp only [route] at h ⊢; split
    · rename_i hc; simp only [hc, ite_true] at h; exact ih h
    · rfl
  | pointerDown p b clicks mods =>
    cases b with
    | primary =>
      simp only [route] at h ⊢
      split
      · rename_i t ht
        simp only [ht] at h
        split
        · rfl
        · rename_i hb
          simp only [hb, Bool.false_eq_true, ite_false] at h
          split at h <;> simp_all [withPointer]
      · rename_i ht; simp only [ht] at h; simp_all [withPointer]
    | secondary => rfl
  | key k mods =>
    cases k <;> simp only [route] at h ⊢ <;>
      first
        | (rw [tab_menu] at h; exact absurd h hne)
        | (unfold keyRoute at h ⊢; split
           · rfl
           · rename_i hk; simp only [hk] at h; rw [keyScrollState_menu] at h; exact absurd h hne)
  | insertText str rep =>
    simp only [route] at h ⊢
    unfold textRoute at h ⊢; split
    · rfl
    · rename_i hk; simp only [hk] at h; exact absurd h hne
  | menuClose p => rfl
  | pointerUp p b mods =>
    cases b
    · simp only [route] at h ⊢
      split at h <;> (try split at h) <;> simp_all [withPointer]
    · simp only [route] at h ⊢
  | _ =>
    first
      | rfl
      | (simp only [route] at h ⊢
         first
           | rfl
           | exact absurd h hne
           | (rw [wheel_menu] at h; exact absurd h hne)
           | (simp_all [withPointer]; done)
           | (split at h <;> simp_all [withPointer]))

/-- **Opening a menu changes no app state.** A step whose routing opens a control menu (for
instance a secondary click on a control with a menu, `secondary_opens`) leaves the app state as
it was and asks the host for nothing; only choosing an item (`menuSelect`) reaches `update`. -/
theorem step_open_quiet (app : App S) (cfg : Config) (s : State S) (e : Event) {r : ControlRef}
    (h : (route cfg.metrics s e).1.ui.menu = some r) (hne : s.ui.menu ≠ some r)
    (hw : e.isWorld = false) :
    (step app cfg s e).1.app = s.app ∧ (step app cfg s e).2 = [] := by
  have hq := route_open_quiet cfg.metrics s e h hne
  have ha : admit app s e = { app := s.app, world := s.world } := by
    cases e <;> simp_all [Event.isWorld, admit]
  have hl := (route_laid cfg.metrics s e).2
  unfold step
  rcases hrt : route cfg.metrics s e with ⟨s1, acts⟩
  rw [hrt] at hq hl
  simp only at hq hl
  subst hq
  rw [ha]
  dsimp only
  split
  · exact ⟨hl, rfl⟩
  · simp only [act, List.isEmpty_nil, ite_true]
    simp

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
      (try split) <;> (try split) <;>
      first | contradiction | simp [tab_surfaces, wheel_fst, secondaryDown_fst, keyRoute_fst, textRoute_fst]

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
      · intro hd; rw [ack_delivered] at hd; rw [ack_app]; exact hear_kept app _ _ (fun _ => rfl) hd
    · intro _; exact ack_app _ _
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
    from fun s h => this (es ++ frameEvents) (s, []) h
  intro es
  induction es with
  | nil => intro acc h; exact h
  | cons e es ih =>
    intro ⟨s, effs⟩ h
    exact ih _ (step_surfaces app cfg s e h)

end Cairn.Runtime
