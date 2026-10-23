import Cairn.Layout.Bridge

/-! # Checking `Pressable` by evaluation

`Pressable w l` (`Bridge.lean`) is stated with `Laid.Everywhere`, an inductive `Prop`, so it
can't be decided directly. This file gives each condition a `Bool` twin and proves the twin
sound, so for a concrete view, window and metrics an app proves every control pressable with
`by decide +kernel` (the kernel evaluates the layout; no compiler, no extra axiom):

```lean
theorem pressable : ∀ t ∈ targets (layout m w v), hitTest (layout m w v) t.visible.center = some t.control :=
  hitTest_center_of_check (by decide +kernel)
```
-/

namespace Cairn.Layout
open Cairn.Runtime

/-! ## The conditions, as `Bool` -/

def insideB (r o : Rect) : Bool :=
  decide (o.x ≤ r.x) && decide (r.x + r.w ≤ o.x + o.w) && decide (o.y ≤ r.y) &&
    decide (r.y + r.h ≤ o.y + o.h)

def fitsB : Laid → Bool
  | .box r _ st _ kids =>
    let content := r.inset st.padding
    (decide (0 ≤ st.padding.top) && decide (0 ≤ st.padding.right) &&
      decide (0 ≤ st.padding.bottom) && decide (0 ≤ st.padding.left)) &&
    kids.all (fun k => decide (k.rect.w ≤ content.w) && decide (k.rect.h ≤ content.h)) &&
    (decide (st.axis = .stack) ||
      decide ((kids.map fun k => mainOf (Axis.horiz st.axis) k.rect).sum + gaps st.gap kids.length
        ≤ mainOf (Axis.horiz st.axis) content))
  | _ => true

def stackTopB : Laid → Bool
  | .box _ _ st _ kids => !decide (st.axis = .stack) || kids.dropLast.all fun k => k.controls.isEmpty
  | _ => true

def controlLeafB : Laid → Bool
  | .box _ _ _ (some _) kids => (Laid.controlsList kids).isEmpty
  | _ => true

mutual
/-- `p` holds at every node. -/
def allB (p : Laid → Bool) : Laid → Bool
  | l@(.box _ _ _ _ kids) => p l && allListB p kids
  | l@(.text ..) => p l
  | l@(.field ..) => p l
def allListB (p : Laid → Bool) : List Laid → Bool
  | [] => true
  | k :: ks => allB p k && allListB p ks
end

/-- Every condition of `Pressable`, evaluated. -/
def checkPressable (w : Size) (l : Laid) : Bool :=
  insideB l.rect (windowRect w) && allB fitsB l && allB stackTopB l && allB controlLeafB l

/-- Every control's rect is nonempty. -/
def controlsNonempty (l : Laid) : Bool :=
  (targets l).all fun t => decide (0 < t.node.rect.w) && decide (0 < t.node.rect.h)

/-! ## Soundness -/

theorem inside_of_insideB {r o : Rect} (h : insideB r o = true) : r.inside o := by
  simp only [insideB, Bool.and_eq_true, decide_eq_true_eq] at h
  unfold Rect.inside; omega

mutual
theorem everywhere_of_allB {p : Laid → Bool} {P : Laid → Prop} (hp : ∀ l, p l = true → P l) :
    ∀ l, allB p l = true → l.Everywhere P
  | .box r c st ctl kids, h => by
    simp only [allB, Bool.and_eq_true] at h
    exact .intro (hp _ h.1) fun k hk => everywhere_of_allListB hp kids h.2 k hk
  | .text .., h => .intro (hp _ (by simpa only [allB] using h)) (by simp [Laid.children])
  | .field .., h => .intro (hp _ (by simpa only [allB] using h)) (by simp [Laid.children])
theorem everywhere_of_allListB {p : Laid → Bool} {P : Laid → Prop} (hp : ∀ l, p l = true → P l) :
    ∀ ks, allListB p ks = true → ∀ k ∈ ks, k.Everywhere P
  | [], _, k, hk => by simp at hk
  | k' :: ks, h, k, hk => by
    simp only [allListB, Bool.and_eq_true] at h
    match hk with
    | .head _ => exact everywhere_of_allB hp _ h.1
    | .tail _ hk => exact everywhere_of_allListB hp ks h.2 k hk
end

theorem fits_of_fitsB : ∀ l, fitsB l = true → Fits l
  | .box r c st ctl kids, h => by
    simp only [fitsB, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, List.all_eq_true] at h
    obtain ⟨⟨hpad, hk⟩, hm⟩ := h
    refine ⟨by omega, fun k hk' => hk k hk', fun hs => ?_⟩
    rcases hm with hm | hm
    · exact absurd hm hs
    · exact hm
  | .text .., _ => trivial
  | .field .., _ => trivial

theorem stackTop_of_stackTopB : ∀ l, stackTopB l = true → StackTop l
  | .box r c st ctl kids, h => by
    simp only [stackTopB, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not,
      List.all_eq_true, List.isEmpty_iff] at h
    intro hs k hk
    rcases h with h | h
    · exact absurd hs h
    · exact h k hk
  | .text .., _ => trivial
  | .field .., _ => trivial

theorem controlLeaf_of_controlLeafB : ∀ l, controlLeafB l = true → ControlLeaf l
  | .box r c st (some k) kids, h => by
    simp only [controlLeafB, List.isEmpty_iff] at h; exact h
  | .box r c st none kids, _ => trivial
  | .text .., _ => trivial
  | .field .., _ => trivial

/-- **The checker is sound.** -/
theorem pressable_of_check {w : Size} {l : Laid} (h : checkPressable w l = true) :
    Pressable w l := by
  simp only [checkPressable, Bool.and_eq_true] at h
  obtain ⟨⟨⟨hi, hf⟩, hs⟩, hc⟩ := h
  exact ⟨inside_of_insideB hi, everywhere_of_allB fits_of_fitsB l hf,
    everywhere_of_allB stackTop_of_stackTopB l hs, everywhere_of_allB controlLeaf_of_controlLeafB l hc⟩

/-- **Every control is pressable at its centre**, for a laid-out view the checker accepts. -/
theorem hitTest_center_of_check {m : TextMetrics} {w : Size} {n : Node}
    (h : (checkPressable w (layout m w n) && controlsNonempty (layout m w n)) = true) :
    ∀ t ∈ targets (layout m w n), hitTest (layout m w n) t.visible.center = some t.control := by
  simp only [Bool.and_eq_true] at h
  intro t ht
  have hne := h.2
  simp only [controlsNonempty, List.all_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hne
  exact hitTest_center_of_pressable (pressable_of_check h.1) ht (hne t ht)

end Cairn.Layout
