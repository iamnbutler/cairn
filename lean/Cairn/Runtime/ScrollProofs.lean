import Cairn.Runtime.Proofs

/-! Theorems about scrolling and `appear` (docs/runtime.md, "Scrolling" and "Appear"): every
offset stays within its box after every step, a scroll changes nothing but the `UI`, Tab brings
the focus into view, and appear moves are exactly the marked controls that came on screen. -/

namespace Cairn.Runtime

variable {S : Type}

/-! ## The clamp -/

/-- Every offset the runtime keeps is for a scroll box of `laid`, within
`[0, max 0 (content − viewport)]` of that box. -/
def Clamped (laid : Laid) (ui : UI) : Prop :=
  ∀ e ∈ ui.scroll, ∃ sc ∈ scrollersOf laid, sc.ref = e.1 ∧ 0 ≤ e.2 ∧
    e.2 ≤ max 0 (sc.content - sc.viewport)

theorem clampOff_mem (o : Int) (sc : Scroller) :
    0 ≤ clampOff o sc.limit ∧ clampOff o sc.limit ≤ max 0 (sc.content - sc.viewport) := by
  unfold clampOff Scroller.limit; omega

theorem clampScroll_clamped (scs : List Scroller) (offs : List (ControlRef × Int)) :
    ∀ e ∈ clampScroll scs offs, ∃ sc ∈ scs, sc.ref = e.1 ∧ 0 ≤ e.2 ∧
      e.2 ≤ max 0 (sc.content - sc.viewport) := by
  intro e he
  simp only [clampScroll, List.mem_filterMap, Option.map_eq_some_iff] at he
  obtain ⟨x, -, sc, hf, rfl⟩ := he
  have hp := List.find?_some hf
  simp only [decide_eq_true_eq] at hp
  exact ⟨sc, List.mem_of_find?_eq_some hf, hp, clampOff_mem _ _⟩

theorem fixUI_clamped (laid : Laid) (pointer : Option Point) (ui : UI) :
    Clamped laid (fixUI laid pointer ui) :=
  clampScroll_clamped _ _

theorem clamped_settle (app : App S) (cfg : Config) (st : S) (pointer : Option Point) (ui0 : UI)
    (fuel : Nat) (ui : UI) (s : State S)
    (h : (s.ui, s.laid) = settle app cfg st pointer ui0 fuel ui) : Clamped s.laid s.ui := by
  obtain ⟨l, hl⟩ := settle_spec app cfg st pointer ui0 fuel ui
  rw [hl] at h
  simp only [Prod.mk.injEq] at h
  obtain ⟨h1, h2⟩ := h
  rw [h1, h2]; exact fixUI_clamped l pointer ui0

/-- **Offsets are clamped** at start. -/
theorem start_clamped (app : App S) (cfg : Config) (size : Size) (scale : Nat) :
    Clamped (start app cfg size scale).laid (start app cfg size scale).ui :=
  clamped_settle app cfg app.init none _ settleFuel _ _ rfl

/-- **Offsets are clamped** after every step: each offset the runtime keeps belongs to a scroll
box on screen and lies within `[0, max 0 (content − viewport)]` of it. -/
theorem step_clamped (app : App S) (cfg : Config) (s : State S) (e : Event)
    (h : Clamped s.laid s.ui) :
    Clamped (step app cfg s e).1.laid (step app cfg s e).1.ui := by
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
      simp only; rw [hui, hl]; exact h
    · exact clamped_settle app cfg _ _ _ _ _ (State.mk ..) rfl

theorem steps_clamped (app : App S) (cfg : Config) (s : State S) (es : List Event)
    (h : Clamped s.laid s.ui) : Clamped (steps app cfg s es).1.laid (steps app cfg s es).1.ui := by
  unfold steps
  suffices ∀ (es : List Event) (acc : State S × List Effect), Clamped acc.1.laid acc.1.ui →
      Clamped (es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e'))
        acc).1.laid
      (es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e')) acc).1.ui
    from this (es ++ frameEvents) (s, []) h
  intro es
  induction es with
  | nil => intro acc h; exact h
  | cons e es ih =>
    intro acc h
    exact ih _ (step_clamped app cfg acc.1 e h)

/-! ## A scroll goes nowhere near the app -/

theorem route_scroll (m : TextMetrics) (s : State S) (p : Point) (dx dy : Int) :
    route m s (.scroll p dx dy) = (wheel s p dx dy, []) := rfl

/-- **A scroll changes no app state**: a wheel or trackpad event leaves the app's state and the
world as they were and issues no effects (so no request, no timer, and no appear move: those
come only from `Event.frame`). -/
theorem step_scroll (app : App S) (cfg : Config) (s : State S) (p : Point) (dx dy : Int) :
    (step app cfg s (.scroll p dx dy)).1.app = s.app ∧
    (step app cfg s (.scroll p dx dy)).1.world = s.world ∧
    (step app cfg s (.scroll p dx dy)).2 = [] := by
  obtain ⟨ui, hw⟩ := wheel_eq s p dx dy
  simp only [step, route_scroll, hw, admit, List.isEmpty_nil, Bool.not_false, Bool.true_and,
    act, ↓reduceIte, Bool.false_eq_true, applyFocus, requestedFocus, List.foldl_nil]
  split <;> simp

/-! ## Tab brings the focus into view -/

/-- **Reveal.** From a clamped offset `cur`, `revealOff` moves a box so that a rect of its
content that fits in the box lies wholly inside it: its start, moved by the change of offset,
is within `[0, viewport − length]`. (`tab` does this for each box around the control it
focuses, innermost first.) -/
theorem revealOff_shows (sc : Scroller) (cur : Int) (q : Rect)
    (hcur : 0 ≤ cur ∧ cur ≤ sc.limit) (hfit : mainLen sc.horiz q ≤ sc.viewport)
    (hin : 0 ≤ cur + (mainStart sc.horiz q - mainStart sc.horiz sc.rect) ∧
      cur + (mainStart sc.horiz q - mainStart sc.horiz sc.rect) + mainLen sc.horiz q ≤ sc.content) :
    0 ≤ mainStart sc.horiz q - mainStart sc.horiz sc.rect - (revealOff sc cur q - cur) ∧
      mainStart sc.horiz q - mainStart sc.horiz sc.rect - (revealOff sc cur q - cur) +
        mainLen sc.horiz q ≤ sc.viewport := by
  simp only [Scroller.limit] at hcur
  simp only [revealOff, clampOff, Scroller.limit]
  split <;> (try split) <;> omega

/-! ## Appear -/

theorem route_frame (m : TextMetrics) (s : State S) :
    route m s .frame = ({ s with seen := appearRefs s.laid }, appearing s.laid s.seen) := rfl

theorem leave_noAppear (s : State S) (n : Option ControlRef) (c : ControlRef) :
    Action.appear c ∉ leave s n := by
  unfold leave; split <;> (try split) <;> simp

theorem onField_noAppear (s : State S) (ops : Target → List TextOp) (c : ControlRef) :
    Action.appear c ∉ onField s ops := by
  unfold onField; split <;> (try split) <;> simp

theorem keyActions_noAppear (s : State S) (k : Key) (mods : Mods) (c : ControlRef) :
    Action.appear c ∉ keyActions s k mods := by
  unfold keyActions; split <;> (try split) <;> (try split) <;> simp

theorem textActions_noAppear (s : State S) (str : String) (rep : Option (Nat × Nat))
    (c : ControlRef) : Action.appear c ∉ textActions s str rep := by
  unfold textActions; split <;> (try split) <;> (try split) <;> simp

theorem tab_noAppear (s : State S) (back : Bool) (c : ControlRef) :
    Action.appear c ∉ (tab s back).2 := by
  unfold tab; split
  · simp
  · simp only [List.mem_append, not_or]
    exact ⟨leave_noAppear _ _ _, by split <;> simp⟩

/-- Only the frame event routes appear moves (a window surface's events are routed as the
window's own, and a frame event is never sent by the host). -/
theorem route_appear (m : TextMetrics) (s : State S) (e : Event) (c : ControlRef)
    (h : Action.appear c ∈ (route m s e).2) : e = .frame ∨ ∃ p e', e = .surface p e' := by
  cases e with
  | frame => exact .inl rfl
  | surface p e' => exact .inr ⟨p, e', rfl⟩
  | key k mods =>
    exfalso; revert h
    cases k <;> simp only [route] <;>
      first | exact tab_noAppear _ _ _ | exact keyActions_noAppear _ _ _ _
  | pointerDown p b n mods =>
    exfalso; revert h
    cases b <;> simp only [route] <;> (try split) <;> (try split) <;>
      simp [leave_noAppear]
  | pointerUp p b mods =>
    exfalso; revert h
    cases b <;> simp only [route] <;> (try split) <;> (try split) <;> (try split) <;> simp
  | _ =>
    exfalso; revert h
    simp only [route] <;> (try split) <;> (try split) <;> (try split) <;>
      simp [onField_noAppear, textActions_noAppear]

/-- Only the frame event changes what was seen. -/
theorem route_seen (m : TextMetrics) (s : State S) (e : Event) (h : e ≠ .frame) :
    (route m s e).1.seen = s.seen := by
  induction e with
  | frame => exact absurd rfl h
  | surface p e ih =>
    simp only [route]; split
    · rename_i hc
      have : e ≠ .frame := by
        rintro rfl; simp [Event.isLocal] at hc
      exact ih this
    · rfl
  | _ =>
    rw [route.eq_def] <;> (try simp only [withPointer]) <;> (try split) <;> (try split) <;>
      (try split) <;> (try split) <;>
      first | contradiction | simp [tab, wheel, keyScrollState] <;> (try split) <;>
        (try split) <;> (try split) <;> rfl

/-- A step keeps what routing made of `seen`. -/
theorem step_seen (app : App S) (cfg : Config) (s : State S) (e : Event) :
    (step app cfg s e).1.seen = (route cfg.metrics s e).1.seen := by
  unfold step
  generalize route cfg.metrics s e = r
  obtain ⟨s1, acts⟩ := r
  dsimp only
  split <;> rfl

/-- After a frame event, `seen` is the appear-marked controls on screen at that frame; no other
event changes it. -/
theorem step_frame_seen (app : App S) (cfg : Config) (s : State S) :
    (step app cfg s .frame).1.seen = appearRefs s.laid := by
  rw [step_seen, route_frame]

theorem step_seen_other (app : App S) (cfg : Config) (s : State S) (e : Event) (h : e ≠ .frame) :
    (step app cfg s e).1.seen = s.seen := by
  rw [step_seen, route_seen _ _ _ h]

/-- **Appear, exactly.** A frame delivers `appear c` exactly when `c` is a control marked
`Control.appear` with a visible part on screen now, and was not one at the last frame. (A
control is on screen only while its move is enabled, by the app's presence claims, so "visible
and enabled".) -/
theorem appear_iff (m : TextMetrics) (s : State S) (c : ControlRef) :
    Action.appear c ∈ (route m s .frame).2 ↔
      (∃ t ∈ targets s.laid, t.control.appear = true ∧ t.visible.nonempty ∧ t.ref = c) ∧
        c ∉ s.seen := by
  rw [route_frame, mem_appearing]
  constructor
  · rintro ⟨c', hc, hn, t, ht, ha, hv, rfl⟩
    cases hc
    exact ⟨⟨t, ht, ha, hv, rfl⟩, hn⟩
  · rintro ⟨⟨t, ht, ha, hv, rfl⟩, hn⟩
    exact ⟨t.ref, rfl, hn, t, ht, ha, hv, rfl⟩

/-- The app hears a frame's appear moves through `update`, in paint order, like any other
action (when it has heard the current time, as after any input). -/
theorem step_frame_delivers (app : App S) (cfg : Config) (s : State S)
    (hh : s.world.heard = some s.world.clock) :
    (step app cfg s .frame).1.app = (deliver app.update s.app (appearing s.laid s.seen)).1 := by
  rw [step_delivers app cfg s .frame rfl hh, route_frame]

end Cairn.Runtime
