import Cairn.Layout.Proofs
import Cairn.UI.Hit

/-! # From layout facts to the runtime's `LayoutFacts`

The runtime's pressable theorems (`Cairn.Runtime.hitTest_center`, `click_center_presses`) take
`Cairn.Runtime.LayoutFacts laid t`: the control's visible rect is nonempty and a pointer at its
centre reaches it. This file proves that every control of `layout m w n` satisfies it, given
four conditions an app can check about its view (`Pressable`):

1. **It fits.** In every container, padding is non-negative, each child is no larger than the
   content box, and in a row or column the children plus gaps fit along the main axis
   (`Fits`). This is where the minimum window size comes in. A box that clips and holds only
   text is exempt: its text may overflow (a long title, a label under unusual metrics), but
   the clip keeps everything it paints inside its rect, and text has no controls.
2. **The root is inside the window.**
3. **Stacks keep controls on top.** In a stack, only the last child may contain controls
   (`StackTop`): earlier children are backgrounds that later ones paint over.
4. **Controls are leaves for hit testing.** A box with a control has no controls below it
   (`ControlLeaf`), so a label inside a button routes to the button.

Then every control whose rect is nonempty is pressable at its centre
(`layoutFacts_of_pressable`), and indeed at every point of its visible rect
(`reaches_of_pressable`). -/

namespace Cairn.Layout
open Cairn.Runtime

/-! ## The conditions -/

def _root_.Cairn.Laid.isText : Laid → Bool
  | .text .. => true
  | _ => false

/-- The children of this container fit in its content box, and its padding is non-negative;
or it clips and its children are text, which may overflow it. -/
def Fits : Laid → Prop
  | .box r _ st _ kids =>
    (st.clip = true ∧ ∀ k ∈ kids, k.isText = true) ∨
    let content := r.inset st.padding
    (0 ≤ st.padding.top ∧ 0 ≤ st.padding.right ∧ 0 ≤ st.padding.bottom ∧ 0 ≤ st.padding.left) ∧
    (∀ k ∈ kids, k.rect.w ≤ content.w ∧ k.rect.h ≤ content.h) ∧
    (st.axis ≠ .stack →
      (kids.map fun k => mainOf (Axis.horiz st.axis) k.rect).sum + gaps st.gap kids.length
        ≤ mainOf (Axis.horiz st.axis) content)
  | _ => True

/-- In a stack, only the last child may contain controls. -/
def StackTop : Laid → Prop
  | .box _ _ st _ kids => st.axis = .stack → ∀ k ∈ kids.dropLast, k.controls = []
  | _ => True

/-- A box with a control has no controls below it. -/
def ControlLeaf : Laid → Prop
  | .box _ _ _ (some _) kids => Laid.controlsList kids = []
  | _ => True

/-- What an app shows about its laid-out view so that every control in it is pressable. -/
structure Pressable (w : Size) (l : Laid) : Prop where
  rootInside : l.rect.inside (windowRect w)
  fits : l.Everywhere Fits
  stackTop : l.Everywhere StackTop
  controlLeaf : l.Everywhere ControlLeaf

/-! ## Rects -/

theorem Rect.contains_iff (r : Rect) (p : Point) :
    r.contains p = true ↔ r.x ≤ p.x ∧ p.x < r.x + r.w ∧ r.y ≤ p.y ∧ p.y < r.y + r.h := by
  simp only [Rect.contains, Bool.decide_and, Bool.and_eq_true, decide_eq_true_eq]

theorem Rect.inter_contains_left {a b : Rect} {p : Point} (h : (a.inter b).contains p = true) :
    a.contains p = true := by
  rw [Rect.contains_iff] at h ⊢
  unfold Rect.inter at h; simp only at h; omega

theorem Rect.inter_contains_right {a b : Rect} {p : Point} (h : (a.inter b).contains p = true) :
    b.contains p = true := by
  rw [Rect.contains_iff] at h ⊢
  unfold Rect.inter at h; simp only at h; omega

theorem Rect.contains_of_inside {r o : Rect} {p : Point} (hi : r.inside o)
    (h : r.contains p = true) : o.contains p = true := by
  rw [Rect.contains_iff] at h ⊢; unfold Rect.inside at hi; omega

theorem Rect.inset_inside (r : Rect) {i : Insets} (ht : 0 ≤ i.top) (hr : 0 ≤ i.right)
    (hb : 0 ≤ i.bottom) (hl : 0 ≤ i.left) :
    (r.inset i).inside r := by
  unfold Rect.inset Rect.inside at *; simp only at *; omega

theorem Rect.inside_trans {a b c : Rect} (hab : a.inside b) (hbc : b.inside c) : a.inside c := by
  unfold Rect.inside at *; omega

theorem Rect.inside_inter {r a b : Rect} (ha : r.inside a) (hb : r.inside b) :
    r.inside (a.inter b) := by
  unfold Rect.inside at *; unfold Rect.inter; simp only; omega

theorem Rect.inter_of_inside {r c : Rect} (h : r.inside c) (hw : 0 ≤ r.w) (hh : 0 ≤ r.h) :
    r.inter c = r := by
  unfold Rect.inside at h; unfold Rect.inter
  cases r; simp only at *
  congr 1 <;> omega

theorem Rect.disjoint_contains {a b : Rect} {p : Point} (hd : a.disjoint b)
    (ha : a.contains p = true) (hb : b.contains p = true) : False := by
  rw [Rect.contains_iff] at ha hb; unfold Rect.disjoint at hd; omega

/-! ## Hit entries and targets -/

theorem hitsList_append (o : Option Target) (a b : List Laid) :
    hitsList o (a ++ b) = hitsList o a ++ hitsList o b := by
  induction a with
  | nil => simp only [List.nil_append, hitsList]
  | cons x xs ih => simp only [List.cons_append, hitsList, ih, List.append_assoc]

theorem mem_hitsList {o : Option Target} {h : Hit} :
    ∀ {ls : List Laid}, h ∈ hitsList o ls → ∃ k ∈ ls, h ∈ hitsOf o k
  | [], hh => by simp only [hitsList, List.not_mem_nil] at hh
  | l :: ls, hh => by
    simp only [hitsList, List.mem_append] at hh
    rcases hh with hh | hh
    · exact ⟨l, .head _, hh⟩
    · obtain ⟨k, hk, hh⟩ := mem_hitsList hh
      exact ⟨k, .tail _ hk, hh⟩

theorem mem_targetsList_split {t : Target} :
    ∀ {ls : List Laid}, t ∈ targetsList ls → ∃ pre k post, ls = pre ++ k :: post ∧ t ∈ targetsOf k
  | [], ht => by simp only [targetsList, List.not_mem_nil] at ht
  | l :: ls, ht => by
    simp only [targetsList, List.mem_append] at ht
    rcases ht with ht | ht
    · exact ⟨[], l, ls, rfl, ht⟩
    · obtain ⟨pre, k, post, rfl, hk⟩ := mem_targetsList_split ht
      exact ⟨l :: pre, k, post, rfl, hk⟩

mutual
theorem targetsOf_controls : ∀ l : Laid, (targetsOf l).map (·.control) = l.controls
  | .box r c st ctl kids => by
    cases ctl <;> simp only [targetsOf, List.nil_append, targetsList_controls kids, Laid.controls,
        Option.toList_none, List.cons_append, List.map_cons, Option.toList_some]
  | .text .. => by simp only [targetsOf, List.map_nil, Laid.controls]
  | .field .. => by simp only [targetsOf, List.map_cons, List.map_nil, Laid.controls]
theorem targetsList_controls : ∀ ls : List Laid,
    (targetsList ls).map (·.control) = Laid.controlsList ls
  | [] => by simp only [targetsList, List.map_nil, Laid.controlsList]
  | l :: ls => by
    simp only [targetsList, List.map_append, targetsOf_controls l, targetsList_controls ls,
        Laid.controlsList]
end

theorem targetsOf_eq_nil {l : Laid} (h : l.controls = []) : targetsOf l = [] := by
  rw [← targetsOf_controls, List.map_eq_nil_iff] at h; exact h

theorem targetsList_eq_nil {ls : List Laid} (h : Laid.controlsList ls = []) : targetsList ls = [] := by
  rw [← targetsList_controls, List.map_eq_nil_iff] at h; exact h

theorem mem_targetsOf_box {t : Target} {r c : Rect} {st : Style} {ctl : Option Control}
    {kids : List Laid} (ht : t ∈ targetsOf (.box r c st ctl kids)) :
    (∃ k, ctl = some k ∧ t = ⟨.box r c st ctl kids, k⟩) ∨ t ∈ targetsList kids := by
  cases ctl with
  | none => simp only [targetsOf, List.nil_append] at ht; exact .inr ht
  | some k =>
    simp only [targetsOf, List.singleton_append, List.mem_cons] at ht
    rcases ht with rfl | ht
    · exact .inl ⟨k, rfl, rfl⟩
    · exact .inr ht

theorem _root_.Cairn.Laid.Everywhere.and {P Q : Laid → Prop} {l : Laid} (hp : l.Everywhere P)
    (hq : l.Everywhere Q) : l.Everywhere fun x => P x ∧ Q x := by
  revert hq
  induction hp with
  | intro hP _ ih => exact fun hq => .intro ⟨hP, hq.here⟩ fun k hk => ih k hk (hq.child hk)

/-- A fact holding everywhere holds at every control's node. -/
theorem _root_.Cairn.Laid.Everywhere.target {P : Laid → Prop} {l : Laid} (hE : l.Everywhere P) :
    ∀ t ∈ targetsOf l, P t.node := by
  induction hE with
  | @intro l hP hK ih =>
    intro t ht
    cases l with
    | box r c st ctl kids =>
      rcases mem_targetsOf_box ht with ⟨k, _, rfl⟩ | ht
      · exact hP
      · obtain ⟨pre, k, post, rfl, hk⟩ := mem_targetsList_split ht
        exact ih k (by simp only [Laid.children, List.mem_append, List.mem_cons, true_or,
            or_true]) t hk
    | text => simp only [targetsOf, List.not_mem_nil] at ht
    | field =>
      simp only [targetsOf, List.mem_singleton] at ht
      subst ht; exact hP

/-! ## The argument -/

/-- Everything the argument uses at one node. -/
def Good (l : Laid) : Prop :=
  Fits l ∧ StackTop l ∧ ControlLeaf l ∧ SiblingsDisjoint l ∧ ChildrenInside l ∧ RectNonneg l ∧
    ChildClips l

/-- In a container that fits (and isn't a clipped box of text), each child's rect is inside the
container's rect. -/
theorem Good.child_inside {r c : Rect} {st : Style} {ctl : Option Control} {kids : List Laid}
    (hG : Good (.box r c st ctl kids)) {k : Laid}
    (hk : k ∈ kids) (hnt : k.isText = false) : k.rect.inside r := by
  obtain ⟨hF, -, -, -, hin, -, -⟩ := hG
  rcases hF with ⟨-, htext⟩ | ⟨⟨p1, p2, p3, p4⟩, hsz, hmain⟩
  · rw [htext k hk] at hnt; exact absurd hnt (by decide)
  have hki : k.rect.inside (r.inset st.padding) := hin hsz hmain k hk
  exact Rect.inside_trans hki (Rect.inset_inside r p1 p2 p3 p4)

/-- A text child's hits are inside its parent's rect when the parent fits or clips. -/
theorem Good.text_hit {r c : Rect} {st : Style} {ctl : Option Control} {kids : List Laid}
    (hG : Good (.box r c st ctl kids)) {k : Laid} (hk : k ∈ kids) (ht : k.isText = true)
    {o : Option Target} {h : Hit} {p : Point} (hh : h ∈ hitsOf o k)
    (hc : h.visible.contains p = true) : r.contains p = true := by
  cases k with
  | box => simp only [Laid.isText, Bool.false_eq_true] at ht
  | field => simp only [Laid.isText, Bool.false_eq_true] at ht
  | text kr kc b ts str =>
    simp only [hitsOf, List.mem_singleton] at hh
    subst hh
    have hkr : (Laid.text kr kc b ts str).rect.contains p = true := Rect.inter_contains_left hc
    obtain ⟨hF, -, -, -, hin, -, hcl⟩ := hG
    rcases hF with ⟨hclip, -⟩ | ⟨⟨p1, p2, p3, p4⟩, hsz, hmain⟩
    · have hkc : kc = c.inter r := by
        have := hcl _ hk
        simp only [Laid.clip, Laid.innerClip, innerClip, hclip, ↓reduceIte] at this
        exact this
      have : kc.contains p = true := Rect.inter_contains_right hc
      rw [hkc] at this
      exact Rect.inter_contains_right this
    · have hki : kr.inside (r.inset st.padding) := hin hsz hmain _ hk
      exact Rect.contains_of_inside (Rect.inside_trans hki (Rect.inset_inside r p1 p2 p3 p4)) hkr

/-- Every hit entry in a subtree that contains `p` lies inside the subtree's root rect. -/
theorem hits_inside {l : Laid} (hE : l.Everywhere Good) :
    ∀ (o : Option Target) (h : Hit) (p : Point), h ∈ hitsOf o l → h.visible.contains p = true →
      l.rect.contains p = true := by
  induction hE with
  | @intro l hG hK ih =>
    intro o h p hh hc
    cases l with
    | box r c st ctl kids =>
      simp only [hitsOf, List.mem_append] at hh
      rcases hh with hh | hh
      · split at hh
        · simp only [List.mem_singleton] at hh
          subst hh
          exact Rect.inter_contains_left hc
        · simp only [List.not_mem_nil] at hh
      · obtain ⟨k, hk, hh⟩ := mem_hitsList hh
        cases hkt : k.isText
        · have hkp := ih k (by simp only [Laid.children, hk]) _ h p hh hc
          exact Rect.contains_of_inside (hG.child_inside hk hkt) hkp
        · exact hG.text_hit hk hkt hh hc
    | text =>
      simp only [hitsOf, List.mem_singleton] at hh
      subst hh; exact Rect.inter_contains_left hc
    | field =>
      simp only [hitsOf, List.mem_singleton] at hh
      subst hh; exact Rect.inter_contains_left hc

/-- `Reaches`, for any list of hit entries. -/
def ReachesIn (hs : List Hit) (t : Target) (p : Point) : Prop :=
  ∃ pre post, hs = pre ++ ⟨t.visible, some t⟩ :: post ∧ t.visible.contains p = true ∧
    ∀ h ∈ post, h.visible.contains p = true → h.owner = some t

theorem mem_dropLast {α : Type} {pre post : List α} {k k' : α} (h : k' ∈ post) :
    k ∈ (pre ++ k :: post).dropLast := by
  cases post with
  | nil => simp only [List.not_mem_nil] at h
  | cons x xs => simp only [ne_eq, reduceCtorEq, not_false_eq_true,
      List.dropLast_append_of_ne_nil, List.dropLast_cons_cons,
    List.mem_append, List.mem_cons, true_or, or_true]

/-- In a tree where every node is `Good`, a pointer anywhere in a control's visible rect reaches
that control. -/
theorem reachesIn_of_good {l : Laid} (hE : l.Everywhere Good) :
    ∀ (o : Option Target) (t : Target) (p : Point), t ∈ targetsOf l →
      t.visible.contains p = true → ReachesIn (hitsOf o l) t p := by
  induction hE with
  | @intro l hG hK ih =>
    intro o t p ht hc
    cases l with
    | text => simp only [targetsOf, List.not_mem_nil] at ht
    | field =>
      simp only [targetsOf, List.mem_singleton] at ht
      subst ht
      exact ⟨[], [], by simp only [hitsOf, Target.visible, List.nil_append], hc,
          by simp only [List.not_mem_nil, false_implies, implies_true]⟩
    | box r c st ctl kids =>
      rcases mem_targetsOf_box ht with ⟨k, rfl, rfl⟩ | hkids
      · -- The control itself: nothing below it is a control, so everything after it is its own.
        have hleaf : targetsList kids = [] := targetsList_eq_nil hG.2.2.1
        refine ⟨[], hitsList (some ⟨.box r c st (some k) kids, k⟩) kids, ?_, hc, ?_⟩
        · simp only [hitsOf, paints, Option.isSome_some, Bool.or_true, ↓reduceIte,
            List.cons_append, List.nil_append,
    Target.visible]
        · intro h hh _
          rcases hitsList_owner _ kids h hh with e | ⟨t', ht', _⟩
          · exact e
          · simp only [hleaf, List.not_mem_nil] at ht'
      · -- A box with a control has no controls below it, so this one has none.
        cases ctl with
        | some kc => rw [targetsList_eq_nil hG.2.2.1] at hkids; simp only [List.not_mem_nil] at hkids
        | none =>
        obtain ⟨pre, k, post, rfl, htk⟩ := mem_targetsList_split hkids
        have hkE := hK k (by simp only [Laid.children, List.mem_append, List.mem_cons, true_or,
            or_true])
        obtain ⟨preK, postK, hEq, _, hpostK⟩ :=
          ih k (by simp only [Laid.children, List.mem_append, List.mem_cons, true_or,
              or_true]) o t p htk hc
        have hkp : k.rect.contains p = true :=
          hits_inside hkE o ⟨t.visible, some t⟩ p (by rw [hEq]; simp only [List.mem_append,
              List.mem_cons, true_or, or_true]) hc
        -- Nothing painted in a later sibling contains `p`.
        have hlater : ∀ h ∈ hitsList o post, h.visible.contains p = true → False := by
          intro h hh hcp
          obtain ⟨k', hk', hh⟩ := mem_hitsList hh
          have hk'p := hits_inside (hK k' (by simp only [Laid.children, List.mem_append,
              List.mem_cons, hk', or_true])) o h p hh hcp
          by_cases hax : st.axis = .stack
          · have hnil := hG.2.1 hax k (mem_dropLast hk')
            simp only [targetsOf_eq_nil hnil, List.not_mem_nil] at htk
          · have hpw := hG.2.2.2.1 hax
            rw [List.pairwise_append] at hpw
            have hd := (List.pairwise_cons.1 hpw.2.1).1 k' hk'
            exact Rect.disjoint_contains hd hkp hk'p
        refine ⟨(if paints st none then [⟨(Laid.box r c st none (pre ++ k :: post)).visible, o⟩]
            else []) ++ hitsList o pre ++ preK, postK ++ hitsList o post, ?_, hc, ?_⟩
        · simp only [hitsOf, hitsList_append, hitsList, hEq]
          simp only [List.append_assoc, List.cons_append]
        · intro h hh hcp
          rcases List.mem_append.1 hh with hh | hh
          · exact hpostK h hh hcp
          · exact (hlater h hh hcp).elim

/-- In a tree where every node is `Good` and the root is inside its clip, each control's rect
is inside its clip. -/
theorem rect_inside_clip {l : Laid} (hE : l.Everywhere Good) :
    l.rect.inside l.clip → ∀ t ∈ targetsOf l, t.node.rect.inside t.node.clip := by
  induction hE with
  | @intro l hG hK ih =>
    intro hrc t ht
    cases l with
    | text => simp only [targetsOf, List.not_mem_nil] at ht
    | field =>
      simp only [targetsOf, List.mem_singleton] at ht
      subst ht; exact hrc
    | box r c st ctl kids =>
      rcases mem_targetsOf_box ht with ⟨k, _, rfl⟩ | ht
      · exact hrc
      · obtain ⟨pre, k, post, rfl, htk⟩ := mem_targetsList_split ht
        have hkmem : k ∈ pre ++ k :: post := by simp only [List.mem_append, List.mem_cons,
            true_or, or_true]
        have hkE := hK k (by simp only [Laid.children, List.mem_append, List.mem_cons, true_or,
            or_true])
        have hnt : k.isText = false := by
          cases k with
          | text => simp only [targetsOf, List.not_mem_nil] at htk
          | _ => rfl
        have hki : k.rect.inside r := hG.child_inside hkmem hnt
        have hclip : k.clip = innerClip st c r := hG.2.2.2.2.2.2 k hkmem
        refine ih k (by simp only [Laid.children, List.mem_append, List.mem_cons, true_or,
            or_true]) ?_ t htk
        rw [hclip]
        simp only [Laid.rect] at hrc
        unfold innerClip; split
        · exact Rect.inside_inter (Rect.inside_trans hki hrc) hki
        · exact Rect.inside_trans hki hrc

/-! ## The bridge -/

theorem layout_good {m : TextMetrics} {w : Size} {n : Node} (hp : Pressable w (layout m w n)) :
    (layout m w n).Everywhere Good :=
  hp.fits.and <| hp.stackTop.and <| hp.controlLeaf.and <| (layout_siblingsDisjoint m w n).and <|
    (layout_childrenInside m w n).and <| (layout_rectNonneg m w n).and (layout_childClips m w n)

/-- **Reaching, from layout.** If the view is `Pressable`, a pointer at any point of a control's
visible rect reaches that control. -/
theorem reaches_of_pressable {m : TextMetrics} {w : Size} {n : Node}
    (hp : Pressable w (layout m w n)) {t : Target} (ht : t ∈ targets (layout m w n)) {p : Point}
    (hc : t.visible.contains p = true) : Reaches (layout m w n) t p :=
  reachesIn_of_good (layout_good hp) none t p ht hc

/-- **The bridge.** If the view is `Pressable`, every control whose rect is nonempty satisfies
the runtime's `LayoutFacts`: its visible rect is its whole rect, and a pointer at the centre
reaches it. So `Cairn.Runtime.hitTest_center` and `click_center_presses` apply. -/
theorem layoutFacts_of_pressable {m : TextMetrics} {w : Size} {n : Node}
    (hp : Pressable w (layout m w n)) {t : Target} (ht : t ∈ targets (layout m w n))
    (hne : t.node.rect.nonempty) : LayoutFacts (layout m w n) t := by
  have hin : t.node.rect.inside t.node.clip :=
    rect_inside_clip (layout_good hp) (by rw [layout_rootClip]; exact hp.rootInside) t ht
  have hrn : RectNonneg t.node := (layout_rectNonneg m w n).target t ht
  have hvis : t.visible = t.node.rect := by
    simp only [Target.visible, Laid.visible]; exact Rect.inter_of_inside hin hrn.1 hrn.2
  have hne' : t.visible.nonempty := by rw [hvis]; exact hne
  exact ⟨hne', reaches_of_pressable hp ht (Rect.contains_center hne')⟩

/-- And so hit testing at the centre of such a control returns it. -/
theorem hitTest_center_of_pressable {m : TextMetrics} {w : Size} {n : Node}
    (hp : Pressable w (layout m w n)) {t : Target} (ht : t ∈ targets (layout m w n))
    (hne : t.node.rect.nonempty) :
    hitTest (layout m w n) t.visible.center = some t.control :=
  hitTest_center (layoutFacts_of_pressable hp ht hne)

end Cairn.Layout
