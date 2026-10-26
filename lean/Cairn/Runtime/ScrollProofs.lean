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

theorem fixUI_clamped (laid : Laid) (pointer : Option Point) (ui : UI) (keep : List ControlRef) :
    Clamped laid (fixUI laid pointer ui keep) :=
  clampScroll_clamped _ _

theorem clamped_settle (app : App S) (cfg : Config) (st : S) (pointer : Option Point) (ui0 : UI)
    (fuel : Nat) (ui : UI) (s : State S)
    (h : (s.ui, s.laid) = settle app cfg st pointer ui0 fuel ui) : Clamped s.laid s.ui := by
  obtain ⟨l, hl⟩ := settle_spec app cfg st pointer ui0 fuel ui
  rw [hl] at h
  simp only [Prod.mk.injEq] at h
  obtain ⟨h1, h2⟩ := h
  rw [h1, h2]; exact fixUI_clamped l pointer ui0 _

theorem clamped_settleAll (app : App S) (cfg : Config) (st : S) (pointer : Option Point)
    (ui0 ui : UI) (s : State S)
    (h : (s.ui, s.laid) = settleAll app cfg st pointer ui0 ui) : Clamped s.laid s.ui := by
  obtain ⟨l, hl⟩ := settleAll_spec app cfg st pointer ui0 ui
  rw [hl] at h
  simp only [Prod.mk.injEq] at h
  obtain ⟨h1, h2⟩ := h
  rw [h1, h2]; exact fixUI_clamped l pointer ui0 _

theorem clamped_lay (app : App S) (cfg : Config) (st : S) (pointer : Option Point)
    (goals : List (ControlRef × ScrollTarget)) (ui1 : UI) (s : State S)
    (h : (s.ui, s.laid) = lay app cfg st pointer goals ui1) : Clamped s.laid s.ui := by
  obtain ⟨l, u, hl, -, -⟩ := lay_spec app cfg st pointer goals ui1
  rw [hl] at h
  simp only [Prod.mk.injEq] at h
  obtain ⟨h1, h2⟩ := h
  rw [h1, h2]; exact fixUI_clamped l pointer u _

/-- **Offsets are clamped** at start. -/
theorem start_clamped (app : App S) (cfg : Config) (size : Size) (scale : Nat) :
    Clamped (start app cfg size scale).laid (start app cfg size scale).ui :=
  clamped_settleAll app cfg app.init none _ _ _ rfl

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
    · exact clamped_lay app cfg _ _ _ _ (State.mk ..) rfl

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

/-! ## Scrolling to a place (`Effect.scrollTo`) -/

theorem scrollOf_setScroll (ui : UI) (r : ControlRef) (o : Int) : (ui.setScroll r o).scrollOf r = o := by
  unfold UI.setScroll
  split
  · assumption
  · simp [UI.scrollOf]

/-- **`start` lands at 0**, for a box on screen. -/
theorem aimOff_start {laid : Laid} {ui : UI} {r : ControlRef} {sc : Scroller}
    (h : (scrollersOf laid).find? (fun sc => decide (sc.ref = r)) = some sc) :
    aimOff laid ui r .start = some 0 := by
  simp only [aimOff, h]

/-- **`finish` lands at the box's limit**, `max 0 (content − viewport)`: the content's end at the
box's end. -/
theorem aimOff_finish {laid : Laid} {ui : UI} {r : ControlRef} {sc : Scroller}
    (h : (scrollersOf laid).find? (fun sc => decide (sc.ref = r)) = some sc) :
    aimOff laid ui r .finish = some sc.limit := by
  simp only [aimOff, h]

/-- **`key k` lands at the row's top**: for a virtual list on screen whose row `i` has key `k`,
the offset is the row's top in the heights the runtime knows, clamped as every offset is. -/
theorem aimOff_key {laid : Laid} {ui : UI} {r : ControlRef} {sc : Scroller} {ll : LaidList}
    {k i : Nat} (hs : (scrollersOf laid).find? (fun sc => decide (sc.ref = r)) = some sc)
    (hl : (listsOf laid).find? (fun ll => decide (ll.ref = r)) = some ll)
    (hi : ll.info.keys.findIdx? (· == k) = some i) :
    aimOff laid ui r (.key k) = some (clampOff
      ((VList.model ll.info.keys (ui.listOf r) ll.info.estimate).top i) sc.limit) := by
  simp only [aimOff, hs, hl, hi,
    VList.Model.topF_eq _ (VList.model_good ll.info.keys (ui.listOf r) ll.info.estimate).1.sorted]

/-- **Clamped as every offset is**: an aimed offset lies in `[0, max 0 (content − viewport)]` of
the box it names. -/
theorem aimOff_clamped {laid : Laid} {ui : UI} {r : ControlRef} {t : ScrollTarget} {o : Int}
    (h : aimOff laid ui r t = some o) :
    ∃ sc ∈ scrollersOf laid, sc.ref = r ∧ 0 ≤ o ∧ o ≤ max 0 (sc.content - sc.viewport) := by
  unfold aimOff at h
  split at h
  · nomatch h
  · rename_i sc hs
    have hm := List.mem_of_find?_eq_some hs
    have hr := List.find?_some hs
    simp only [decide_eq_true_eq] at hr
    have hlim : 0 ≤ sc.limit := by unfold Scroller.limit; omega
    refine ⟨sc, hm, hr, ?_⟩
    split at h
    · cases h; omega
    · cases h; exact ⟨hlim, by unfold Scroller.limit; omega⟩
    · split at h
      · nomatch h
      · split at h
        · nomatch h
        · cases h; exact clampOff_mem _ _

/-- A request for a box on screen sets its offset to the aimed one (the last request wins). -/
theorem aimScroll_single (laid : Laid) (ui : UI) (r : ControlRef) (t : ScrollTarget) {o : Int}
    (h : aimOff laid ui r t = some o) : (aimScroll [(r, t)] laid ui).scrollOf r = o := by
  simp only [aimScroll, List.foldl_cons, List.foldl_nil, h, scrollOf_setScroll]

/-- **The key's row is the one at the top.** Laid at the top of row `i` (in a model whose rows
are at least a point tall), the first row showing is row `i`: so `scrollTo` a key, unclamped,
lays that row first, and it is the row the runtime then keeps still (`VList.keepRow`,
`VList.record_keeps`). -/
theorem firstF_top (M : VList.Model) (hM : M.Good) (hpos : ∀ j, 1 ≤ M.height j) {i : Nat}
    (hi : i < M.count) : M.firstF M.pre (M.top i) = i := by
  obtain ⟨-, -, h3, h4, -, -⟩ := M.window_spec hM (M.top i) (M.top i)
  have hw : (M.window (M.top i) (M.top i)).1 = M.firstF M.pre (M.top i) := rfl
  rw [hw] at h3 h4
  generalize M.firstF M.pre (M.top i) = f at h3 h4
  rcases Nat.lt_trichotomy f i with hlt | heq | hgt
  · have := h4 (by omega)
    have := M.top_mono hM.pos (i := f + 1) (j := i) (by omega)
    omega
  · exact heq
  · have := h3 i hgt
    have := M.top_succ i
    have := hpos i
    omega

/-! ## A box the app keeps (`App.keepScroll`) -/

theorem find?_clampScroll_none (scs : List Scroller) (offs : List (ControlRef × Int))
    {r : ControlRef} (h : onScreen scs r = false) :
    (clampScroll scs offs).find? (·.1 == r) = none := by
  rw [List.find?_eq_none]
  intro e he
  obtain ⟨sc, hsc, hr, -⟩ := clampScroll_clamped scs offs e he
  intro hb
  simp only [beq_iff_eq] at hb
  simp only [onScreen, List.any_eq_false, decide_eq_true_eq] at h
  exact h sc hsc (hr.trans hb)

theorem find?_filter_of {α : Type} (l : List α) (p q : α → Bool)
    (h : ∀ a, q a = true → p a = true) : (l.filter p).find? q = l.find? q := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    by_cases hq : q a = true
    · simp [h a hq, hq]
    · cases hp : p a <;> simp [hp, hq, ih]

theorem find?_keepOff {α : Type} (on : ControlRef → Bool) (keep : List ControlRef)
    (now old : List (ControlRef × α)) {r : ControlRef} (hk : r ∈ keep) (ho : on r = false) :
    (keepOff on keep now old).find? (·.1 == r) =
      (now.find? (·.1 == r)).or (old.find? (·.1 == r)) := by
  unfold keepOff
  rw [List.find?_append, find?_filter_of _ _ _ (fun e he => by
    simp only [beq_iff_eq] at he; subst he; simp [ho, hk])]
  cases hn : now.find? (·.1 == r) with
  | some x => rfl
  | none =>
    simp only [Option.none_or]
    apply find?_filter_of
    intro e he
    simp only [beq_iff_eq] at he; subst he
    have : now.any (fun x => decide (x.1 = e.1)) = false := by
      rw [List.any_eq_false]
      intro x hx hxe
      have := List.find?_eq_none.mp hn x hx
      simp_all
    simp [ho, hk, this]

/-- **A box the app keeps keeps its offset while it is not on screen**: the offset the view
reads for it (`UI.scrollOf`) is the one it had before the repair. -/
theorem fixUI_keeps_offset (laid : Laid) (pointer : Option Point) (ui : UI)
    (keep : List ControlRef) {r : ControlRef} (hk : r ∈ keep)
    (hs : onScreen (scrollersOf laid) r = false) :
    (fixUI laid pointer ui keep).scrollOf r = ui.scrollOf r := by
  simp only [UI.scrollOf, fixUI, find?_clampScroll_none _ _ hs,
    find?_keepOff _ keep _ _ hk hs]
  cases ui.scroll.find? (·.1 == r) <;> rfl

/-- **A list the app keeps keeps what the runtime knew of it** while it is not on screen: its
heights, estimate and anchor, as the view reads them (`UI.listOf`). -/
theorem fixUI_keeps_list (laid : Laid) (pointer : Option Point) (ui : UI)
    (keep : List ControlRef) {r : ControlRef} (hk : r ∈ keep)
    (hs : (recordLists laid).any (fun x => decide (x.1 = r)) = false) :
    (fixUI laid pointer ui keep).listOf r = ui.listOf r := by
  have hn : ((recordLists laid).map fun (x : ControlRef × VList.Known × Int) => (x.1, x.2.1)).find?
      (·.1 == r) = none := by
    rw [List.find?_eq_none]
    intro e he hb
    simp only [List.mem_map] at he
    obtain ⟨x, hx, rfl⟩ := he
    simp only [beq_iff_eq] at hb
    simp only [List.any_eq_false, decide_eq_true_eq] at hs
    exact hs x hx hb
  simp only [UI.listOf, fixUI, hn, find?_keepOff (fun r => (recordLists laid).any fun x => decide (x.1 = r)) keep _ _ hk hs]
  cases ui.lists.find? (·.1 == r) <;> rfl

theorem find?_setOff (offs : List (ControlRef × Int)) {r r' : ControlRef} (o : Int)
    (h : r' ≠ r) : (setOff offs r' o).find? (·.1 == r) = offs.find? (·.1 == r) := by
  have key : ∀ c : Int, (if c = o then offs else (r', o) :: offs.filter fun e => !decide (e.1 = r')).find?
      (·.1 == r) = offs.find? (·.1 == r) := by
    intro c
    split
    · rfl
    · rw [List.find?_cons]
      have : ((r', o).1 == r) = false := by simpa using h
      rw [this]
      apply find?_filter_of
      intro e he
      simp only [beq_iff_eq] at he
      subst he
      simpa using fun h' => h h'.symm
  unfold setOff
  split <;> exact key _

theorem find?_foldl_setOff (recs : List (ControlRef × VList.Known × Int))
    {r : ControlRef} (h : ∀ x ∈ recs, x.1 ≠ r) :
    ∀ offs : List (ControlRef × Int),
      (recs.foldl (fun offs (x : ControlRef × VList.Known × Int) => setOff offs x.1 x.2.2) offs).find?
        (·.1 == r) = offs.find? (·.1 == r) := by
  induction recs with
  | nil => intro offs; rfl
  | cons x xs ih =>
    intro offs
    simp only [List.foldl_cons]
    rw [ih (fun y hy => h y (List.mem_cons_of_mem _ hy)),
      find?_setOff _ _ (h x List.mem_cons_self)]

theorem find?_clampScroll (scs : List Scroller) {r : ControlRef} {sc : Scroller}
    (hs : scs.find? (fun sc => decide (sc.ref = r)) = some sc) :
    ∀ offs : List (ControlRef × Int), (clampScroll scs offs).find? (·.1 == r) =
      (offs.find? (·.1 == r)).map fun e => (e.1, clampOff e.2 sc.limit) := by
  intro offs
  induction offs with
  | nil => rfl
  | cons e es ih =>
    simp only [clampScroll, List.filterMap_cons] at ih ⊢
    by_cases he : e.1 = r
    · subst he
      simp [hs]
    · have : (e.1 == r) = false := by simpa using he
      cases hf : scs.find? (fun sc => decide (sc.ref = e.1)) with
      | none => simp only [List.find?_cons, this]; exact ih
      | some sc' => simp only [Option.map_some, List.find?_cons, this]; exact ih

/-- **A kept box comes back where it was**: a box back on screen with no offset of its own
resumes its kept offset, clamped to its content as every offset is. (A virtual list's is first
corrected by its record, `VList.record`, from what was kept of it, `fixUI_keeps_list`; this is
the box that is no virtual list.) -/
theorem fixUI_revives (laid : Laid) (pointer : Option Point) (ui : UI) (keep : List ControlRef)
    {r : ControlRef} {sc : Scroller} {o : Int}
    (hs : (scrollersOf laid).find? (fun sc => decide (sc.ref = r)) = some sc)
    (hl : (recordLists laid).any (fun x => decide (x.1 = r)) = false)
    (hn : ui.scroll.find? (·.1 == r) = none) (hk : ui.kept.find? (·.1 == r) = some (r, o)) :
    (fixUI laid pointer ui keep).scrollOf r = clampOff o sc.limit := by
  have hrecs : ∀ x ∈ recordLists laid, x.1 ≠ r := by
    simp only [List.any_eq_false, decide_eq_true_eq] at hl
    exact hl
  have hon : onScreen (scrollersOf laid) r = true := by
    simp only [onScreen, List.any_eq_true, decide_eq_true_eq]
    exact ⟨sc, List.mem_of_find?_eq_some hs, by simpa using List.find?_some hs⟩
  have hrev : (revive (scrollersOf laid) ui).find? (·.1 == r) = some (r, o) := by
    unfold revive
    rw [find?_filter_of _ _ _ (fun e he => by
      simp only [beq_iff_eq] at he; subst he
      have : ui.scroll.any (fun x => decide (x.1 = e.1)) = false := by
        rw [List.any_eq_false]
        intro x hx hxe
        have := List.find?_eq_none.mp hn x hx
        simp_all
      simp [hon, this])]
    exact hk
  simp only [UI.scrollOf, fixUI]
  rw [find?_clampScroll _ hs, find?_foldl_setOff _ hrecs, List.find?_append, hn, Option.none_or,
    hrev]
  rfl

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

theorem keyRoute_noAppear (s : State S) (k : Key) (mods : Mods) (c : ControlRef) :
    Action.appear c ∉ (keyRoute s k mods).2 := by
  unfold keyRoute; split
  · simp
  · exact keyActions_noAppear _ _ _ _

theorem textRoute_noAppear (s : State S) (str : String) (rep : Option (Nat × Nat))
    (c : ControlRef) : Action.appear c ∉ (textRoute s str rep).2 := by
  unfold textRoute; split
  · simp
  · exact textActions_noAppear _ _ _ _

theorem keyScrollState_seen (s : State S) (k : Key) (mods : Mods) :
    (keyScrollState s k mods).seen = s.seen := by
  simp only [keyScrollState]; (try split) <;> (try split) <;> (try split) <;> rfl

theorem secondaryDown_seen (s : State S) (p : Point) : (secondaryDown s p).seen = s.seen := by
  unfold secondaryDown; split <;> rfl

theorem keyRoute_seen (s : State S) (k : Key) (mods : Mods) :
    (keyRoute s k mods).1.seen = s.seen := by
  unfold keyRoute; split
  · rfl
  · exact keyScrollState_seen _ _ _

theorem textRoute_seen (s : State S) (str : String) (rep : Option (Nat × Nat)) :
    (textRoute s str rep).1.seen = s.seen := by
  unfold textRoute; split <;> rfl

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
      first | exact tab_noAppear _ _ _ | exact keyRoute_noAppear _ _ _ _
  | pointerDown p b n mods =>
    exfalso; revert h
    cases b <;> simp only [route] <;> (try split) <;> (try split) <;> (try split) <;>
      simp [leave_noAppear]
  | pointerUp p b mods =>
    exfalso; revert h
    cases b <;> simp only [route] <;> (try split) <;> (try split) <;> (try split) <;> simp
  | _ =>
    exfalso; revert h
    simp only [route] <;> (try split) <;> (try split) <;> (try split) <;>
      simp [onField_noAppear, textRoute_noAppear]

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
      first | contradiction | simp [tab, wheel, secondaryDown_seen, keyRoute_seen, textRoute_seen] <;> (try split) <;>
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
