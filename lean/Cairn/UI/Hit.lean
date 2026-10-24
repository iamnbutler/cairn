module

public import Cairn.UI.Node

/-! Hit testing over a laid-out tree.

Paint order is pre-order: a node paints before its children, and children paint in list order,
so later entries are on top. Every node that paints (a box with a background, border or
control, every text run and every field) leaves a *hit entry*: its visible rect
(`rect.inter clip`) and its *owner*, the nearest control at or above it. A point hits the
topmost entry that contains it, and the hit goes to that entry's owner. So a label inside a
button routes to the button, and an opaque panel painted over a button blocks it. -/

@[expose] public section

namespace Cairn.Runtime

/-- A control-bearing node of a laid tree, with its control pulled out. -/
structure Target where
  node : Laid
  control : Control
deriving Inhabited

namespace Target

def ref (t : Target) : ControlRef := t.control.ref
def visible (t : Target) : Rect := t.node.visible

def isField (t : Target) : Bool :=
  match t.node with
  | .field .. => true
  | _ => false

/-- Fields always take focus; other controls do unless their role is static. -/
def focusable (t : Target) : Bool :=
  t.isField || !([Role.group, .text, .heading, .list].contains t.control.role)

end Target

structure Hit where
  visible : Rect
  owner : Option Target
deriving Inhabited

/-- Whether a box leaves a hit entry. Unpainted, control-less boxes are layout only. -/
def paints (style : Style) (control : Option Control) : Bool :=
  style.background.isSome || style.border.isSome || control.isSome

mutual
/-- Hit entries in paint order; `o` is the owner inherited from the ancestors. -/
def hitsOf (o : Option Target) : Laid → List Hit
  | n@(.box _ _ st c cs) =>
    let o' := match c with
      | some k => some ⟨n, k⟩
      | none => o
    (if paints st c then [⟨n.visible, o'⟩] else []) ++ hitsList o' cs
  | n@(.text ..) => [⟨n.visible, o⟩]
  | n@(.field _ _ _ _ c ..) => [⟨n.visible, some ⟨n, c⟩⟩]
def hitsList (o : Option Target) : List Laid → List Hit
  | [] => []
  | l :: ls => hitsOf o l ++ hitsList o ls
end

mutual
/-- Every control in the tree, in paint order. -/
def targetsOf : Laid → List Target
  | n@(.box _ _ _ c cs) =>
    (match c with
      | some k => [⟨n, k⟩]
      | none => []) ++ targetsList cs
  | .text .. => []
  | n@(.field _ _ _ _ c ..) => [⟨n, c⟩]
def targetsList : List Laid → List Target
  | [] => []
  | l :: ls => targetsOf l ++ targetsList ls
end

def hits (laid : Laid) : List Hit := hitsOf none laid
def targets (laid : Laid) : List Target := targetsOf laid

/-- The refs of every control in the tree, in paint order. -/
def refs (laid : Laid) : List ControlRef := (targets laid).map (·.ref)

/-- `r` names a control in `laid`. -/
def present (laid : Laid) (r : ControlRef) : Bool := (refs laid).any fun x => decide (x = r)

/-- `r` names a focusable control in `laid`. -/
def focusableIn (laid : Laid) (r : ControlRef) : Bool :=
  (targets laid).any fun t => decide (t.ref = r) && t.focusable

/-- The first control in paint order with this ref. -/
def find (laid : Laid) (r : ControlRef) : Option Target :=
  (targets laid).find? (fun t => decide (t.ref = r))

/-- The control a point hits: the owner of the topmost hit entry containing it. -/
def hitTarget (laid : Laid) (p : Point) : Option Target :=
  ((hits laid).reverse.find? (·.visible.contains p)).bind (·.owner)

def hitTest (laid : Laid) (p : Point) : Option Control := (hitTarget laid p).map (·.control)

def hitRef (laid : Laid) (p : Point) : Option ControlRef := (hitTarget laid p).map (·.ref)

/-! ## Structure lemmas -/

mutual
theorem hitsOf_owner (o : Option Target) : ∀ (l : Laid) (h : Hit), h ∈ hitsOf o l →
    h.owner = o ∨ ∃ t ∈ targetsOf l, h.owner = some t
  | .box r cl st c cs, h, hm => by
    cases c with
    | none =>
      simp only [hitsOf, targetsOf, List.mem_append, List.nil_append] at hm ⊢
      rcases hm with hm | hm
      · split at hm <;> simp_all
      · exact hitsList_owner o cs h hm
    | some k =>
      simp only [hitsOf, targetsOf, List.mem_append, List.singleton_append] at hm ⊢
      right
      rcases hm with hm | hm
      · split at hm <;> simp_all
      · rcases hitsList_owner _ cs h hm with e | ⟨t, ht, e⟩
        · exact ⟨_, List.mem_cons_self, e⟩
        · exact ⟨t, List.mem_cons_of_mem _ ht, e⟩
  | .text .., h, hm => by simp_all [hitsOf]
  | .field .., h, hm => by simp_all [hitsOf, targetsOf]
theorem hitsList_owner (o : Option Target) : ∀ (ls : List Laid) (h : Hit), h ∈ hitsList o ls →
    h.owner = o ∨ ∃ t ∈ targetsList ls, h.owner = some t
  | [], h, hm => by simp [hitsList] at hm
  | l :: ls, h, hm => by
    simp only [hitsList, targetsList, List.mem_append] at hm ⊢
    rcases hm with hm | hm
    · rcases hitsOf_owner o l h hm with e | ⟨t, ht, e⟩
      · exact .inl e
      · exact .inr ⟨t, .inl ht, e⟩
    · rcases hitsList_owner o ls h hm with e | ⟨t, ht, e⟩
      · exact .inl e
      · exact .inr ⟨t, .inr ht, e⟩
end

mutual
theorem targetsOf_control : ∀ (l : Laid) (t : Target), t ∈ targetsOf l → t.node.control? = some t.control
  | .box r cl st c cs, t, hm => by
    cases c with
    | none => simpa [targetsOf] using targetsList_control cs t (by simpa [targetsOf] using hm)
    | some k =>
      simp only [targetsOf, List.singleton_append, List.mem_cons] at hm
      rcases hm with rfl | hm
      · rfl
      · exact targetsList_control cs t hm
  | .text .., t, hm => by simp [targetsOf] at hm
  | .field .., t, hm => by
    simp only [targetsOf, List.mem_singleton] at hm
    subst hm; rfl
theorem targetsList_control : ∀ (ls : List Laid) (t : Target), t ∈ targetsList ls →
    t.node.control? = some t.control
  | [], t, hm => by simp [targetsList] at hm
  | l :: ls, t, hm => by
    simp only [targetsList, List.mem_append] at hm
    rcases hm with hm | hm
    · exact targetsOf_control l t hm
    · exact targetsList_control ls t hm
end

/-- Every owner of a hit entry is a control of the tree. -/
theorem hits_owner_mem {laid : Laid} {h : Hit} {t : Target} (hm : h ∈ hits laid)
    (ho : h.owner = some t) : t ∈ targets laid := by
  rcases hitsOf_owner none laid h hm with e | ⟨t', ht', e⟩
  · simp_all
  · rw [ho] at e; cases e; exact ht'

/-- The hit test only ever answers with a control of the tree. -/
theorem hitTarget_mem {laid : Laid} {p : Point} {t : Target} (h : hitTarget laid p = some t) :
    t ∈ targets laid := by
  unfold hitTarget at h
  cases hf : (hits laid).reverse.find? (·.visible.contains p) with
  | none => simp [hf] at h
  | some e =>
    simp only [hf, Option.bind_some] at h
    exact hits_owner_mem (List.mem_reverse.mp (List.mem_of_find?_eq_some hf)) h

theorem mem_refs {laid : Laid} {t : Target} (h : t ∈ targets laid) : t.ref ∈ refs laid :=
  List.mem_map_of_mem h

theorem present_iff {laid : Laid} {r : ControlRef} : present laid r = true ↔ r ∈ refs laid := by
  simp [present]

theorem find_mem {laid : Laid} {r : ControlRef} {t : Target} (h : find laid r = some t) :
    t ∈ targets laid ∧ t.ref = r := by
  unfold find at h
  exact ⟨List.mem_of_find?_eq_some h, by simpa using List.find?_some h⟩

theorem hitRef_present {laid : Laid} {p : Point} {r : ControlRef} (h : hitRef laid p = some r) :
    r ∈ refs laid := by
  unfold hitRef at h
  cases ht : hitTarget laid p with
  | none => simp [ht] at h
  | some t => simp [ht] at h; subst h; exact mem_refs (hitTarget_mem ht)

/-! ## Pressability -/

/-- `t` is what a pointer at `p` reaches: `t`'s own hit entry contains `p`, and everything
painted after it that also contains `p` belongs to `t` (its label, its icon). -/
def Reaches (laid : Laid) (t : Target) (p : Point) : Prop :=
  ∃ pre post, hits laid = pre ++ ⟨t.visible, some t⟩ :: post ∧ t.visible.contains p = true ∧
    ∀ h ∈ post, h.visible.contains p = true → h.owner = some t

/-- The facts about a laid tree the pressable theorem needs, for one control `t`: its visible
rect is nonempty, and a pointer at the centre of that rect reaches it. Layout (workstream B)
proves its trees satisfy these for every control of an enabled move at sizes at or above the
minimum. -/
structure LayoutFacts (laid : Laid) (t : Target) : Prop where
  nonempty : t.visible.nonempty
  reaches : Reaches laid t t.visible.center

theorem Rect.contains_center {r : Rect} (h : r.nonempty) : r.contains r.center = true := by
  obtain ⟨hw, hh⟩ := h
  simp only [Rect.contains, Rect.center]
  exact decide_eq_true ⟨by omega, by omega, by omega, by omega⟩

/-- The last element satisfying `q` in `pre ++ a :: post` is `a` or comes after it. -/
theorem find?_reverse_split {α : Type} {q : α → Bool} {pre post : List α} {a : α}
    (ha : q a = true) :
    ∃ b, (pre ++ a :: post).reverse.find? q = some b ∧ (b = a ∨ (b ∈ post ∧ q b = true)) := by
  rw [List.reverse_append, List.reverse_cons, List.append_assoc, List.find?_append]
  cases hf : post.reverse.find? q with
  | none => exact ⟨a, by simp [ha], .inl rfl⟩
  | some b =>
    exact ⟨b, by simp, .inr ⟨List.mem_reverse.mp (List.mem_of_find?_eq_some hf), List.find?_some hf⟩⟩

/-- Hit-test level pressability at a point. -/
theorem hitTarget_of_reaches {laid : Laid} {t : Target} {p : Point} (h : Reaches laid t p) :
    hitTarget laid p = some t := by
  obtain ⟨pre, post, hs, hc, hpost⟩ := h
  obtain ⟨b, hb, hb'⟩ := find?_reverse_split (q := fun h : Hit => h.visible.contains p)
    (pre := pre) (post := post) (a := ⟨t.visible, some t⟩) hc
  unfold hitTarget
  rw [hs, hb]
  rcases hb' with rfl | ⟨hm, hq⟩
  · rfl
  · exact hpost b hm hq

theorem reaches_mem {laid : Laid} {t : Target} {p : Point} (h : Reaches laid t p) :
    t ∈ targets laid := hitTarget_mem (hitTarget_of_reaches h)

/-- **Pressable, hit-test level.** Under the layout facts, hit testing at the centre of a
control's visible rect returns that control. -/
theorem hitTest_center {laid : Laid} {t : Target} (h : LayoutFacts laid t) :
    hitTest laid t.visible.center = some t.control := by
  simp [hitTest, hitTarget_of_reaches h.reaches]

theorem LayoutFacts.contains_center {laid : Laid} {t : Target} (h : LayoutFacts laid t) :
    t.visible.contains t.visible.center = true := Rect.contains_center h.nonempty

end Cairn.Runtime
