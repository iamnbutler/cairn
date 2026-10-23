import Cairn.Text.Wrap

/-! # Theorems about line breaking (`Cairn.Text.Wrap`)

For every text `cs`, width `W` and offsets `o` (any function: nothing here assumes the offsets
are monotone, so it holds for every `TextMetrics`, valid or not):

1. **Lines fit.** `allLines_fit`: every line is at most `W` wide, or is a single scalar (a
   scalar wider than the line, which no break could help).
2. **Lines tile the text.** `allLines_cover` and `allLines_tiles`: the lines are nonempty ranges
   in order, and the text is `g₀ ++ l₀ ++ g₁ ++ l₁ ++ … ++ lₖ ++ gₖ₊₁` with every gap `gᵢ`
   made of break spaces only (possibly empty, where an over-wide word was cut).
3. **Line count.** `lines_length_le`: at most `maxLines` lines.
4. **Keep.** `lines_tail`, `lines_head`: `tail` keeps exactly the last `min n k` of the `k`
   lines, `head` the first. -/

namespace Cairn.Text.Wrap

/-! ## Lines fit -/

/-- A piece or line is good if it fits or is at most one scalar. -/
def Good (o : Nat → Int) (W : Int) (p : Nat × Nat) : Prop := o p.2 - o p.1 ≤ W ∨ p.2 ≤ p.1 + 1

theorem cutGo_spec (o : Nat → Int) (W : Int) (a b : Nat) :
    ∀ (fuel c : Nat), (o c - o a ≤ W ∨ c = a + 1) → a + 1 ≤ c →
      (o (cutGo o W a b fuel c) - o a ≤ W ∨ cutGo o W a b fuel c = a + 1) ∧
        c ≤ cutGo o W a b fuel c ∧ (cutGo o W a b fuel c ≤ b ∨ cutGo o W a b fuel c = c)
  | 0, c, h, _ => by simp only [cutGo, Nat.le_refl, or_true, and_true]; exact h
  | fuel + 1, c, h, hc => by
    simp only [cutGo]
    split
    · next hcond =>
      have := cutGo_spec o W a b fuel (c + 1) (.inl hcond.2) (by omega)
      omega
    · omega

theorem cut_spec (o : Nat → Int) (W : Int) (a b : Nat) :
    (o (cut o W a b) - o a ≤ W ∨ cut o W a b = a + 1) ∧ a + 1 ≤ cut o W a b ∧
      (cut o W a b ≤ b ∨ cut o W a b = a + 1) := by
  have := cutGo_spec o W a b (b - a) (a + 1) (.inr rfl) (Nat.le_refl _)
  simp only [cut]; omega

theorem chunkGo_good (o : Nat → Int) (W : Int) (b : Nat) :
    ∀ (fuel a : Nat), b ≤ a + fuel →
      (∀ p ∈ (chunkGo o W b fuel a).1, Good o W p) ∧ Good o W (chunkGo o W b fuel a).2
  | 0, a, h => by
    simp only [chunkGo, List.not_mem_nil, false_implies, implies_true, true_and]
    right; simp only; omega
  | fuel + 1, a, h => by
    have hc := cut_spec o W a b
    simp only [chunkGo]
    split
    · simp only [List.not_mem_nil, false_implies, implies_true, true_and]
      unfold Good; simp only
      rcases hc with ⟨h1, h2, h3⟩
      rcases h1 with h1 | h1
      · rcases h3 with h3 | h3
        · have : cut o W a b = b := by omega
          rw [this] at h1; left; exact h1
        · right; omega
      · right; omega
    · have ih := chunkGo_good o W b fuel (cut o W a b) (by omega)
      refine ⟨fun p hp => ?_, ih.2⟩
      simp only [List.mem_cons] at hp
      rcases hp with rfl | hp
      · unfold Good; simp only; rcases hc.1 with h1 | h1
        · left; exact h1
        · right; omega
      · exact ih.1 p hp

theorem chunk_good (o : Nat → Int) (W : Int) (w : Nat × Nat) :
    (∀ p ∈ (chunk o W w).1, Good o W p) ∧ Good o W (chunk o W w).2 :=
  chunkGo_good o W w.2 (w.2 - w.1) w.1 (by omega)

theorem fill_good (o : Nat → Int) (W : Int) :
    ∀ (ws : List (Nat × Nat)) (cur : Nat × Nat), Good o W cur → ∀ l ∈ fill o W cur ws, Good o W l
  | [], cur, hc, l, hl => by
    simp only [fill, List.mem_singleton] at hl; subst hl; exact hc
  | w :: ws, cur, hc, l, hl => by
    simp only [fill] at hl
    split at hl
    · next h => exact fill_good o W ws _ (.inl h) l hl
    · simp only [List.mem_cons, List.mem_append] at hl
      rcases hl with rfl | hl | hl
      · exact hc
      · exact (chunk_good o W w).1 l hl
      · exact fill_good o W ws _ (chunk_good o W w).2 l hl

theorem breakAll_good (o : Nat → Int) (W : Int) (ws : List (Nat × Nat)) :
    ∀ l ∈ breakAll o W ws, Good o W l := by
  cases ws with
  | nil => simp only [breakAll, List.not_mem_nil, false_implies, implies_true]
  | cons w ws =>
    intro l hl
    simp only [breakAll, List.mem_append] at hl
    rcases hl with hl | hl
    · exact (chunk_good o W w).1 l hl
    · exact fill_good o W ws _ (chunk_good o W w).2 l hl

/-- **Lines fit.** Every line is at most `W` wide, or is a single scalar. -/
theorem allLines_fit (o : Nat → Int) (W : Int) (cs : List Char) :
    ∀ l ∈ allLines o W cs, o l.2 - o l.1 ≤ W ∨ l.2 ≤ l.1 + 1 :=
  breakAll_good o W _

/-! ## Lines tile the text -/

/-- `Cover sp len p rs`: the ranges `rs` are nonempty and in order, the first starts at or
after `p`, the last ends by `len`, and every index in `[p, len)` outside them satisfies `sp`. -/
inductive Cover (sp : Nat → Prop) (len : Nat) : Nat → List (Nat × Nat) → Prop
  | nil {p : Nat} : p ≤ len → (∀ i, p ≤ i → i < len → sp i) → Cover sp len p []
  | cons {p a b : Nat} {rs : List (Nat × Nat)} : p ≤ a → a < b → (∀ i, p ≤ i → i < a → sp i) →
      Cover sp len b rs → Cover sp len p ((a, b) :: rs)

theorem Cover.le {sp : Nat → Prop} {len p : Nat} {rs : List (Nat × Nat)} (h : Cover sp len p rs) :
    p ≤ len := by
  induction h with
  | nil h _ => exact h
  | cons h1 h2 _ _ ih => omega

/-- Words cover the text: what lies between and around them is break spaces. -/
theorem wordsFrom_cover (cs : List Char) :
    ∀ (rest : List Char) (i : Nat), i + rest.length = cs.length → (∀ k, rest[k]? = cs[i + k]?) →
      ∀ (cur : Option Nat) (p : Nat),
        (match cur with
          | none => p ≤ i ∧ ∀ k, p ≤ k → k < i → cs[k]? = some ' '
          | some a => p ≤ a ∧ a < i ∧ ∀ k, p ≤ k → k < a → cs[k]? = some ' ') →
        Cover (fun k => cs[k]? = some ' ') cs.length p (wordsFrom rest i cur)
  | [], i, hlen, _, none, p, ⟨h1, h2⟩ => by
    simp only [List.length_nil, Nat.add_zero] at hlen
    exact .nil (by omega) (fun k hk hk' => h2 k hk (by omega))
  | [], i, hlen, _, some a, p, ⟨h1, h2, h3⟩ => by
    simp only [List.length_nil, Nat.add_zero] at hlen
    exact .cons h1 h2 h3 (.nil (by omega) (fun k hk hk' => by omega))
  | c :: rest, i, hlen, hat, cur, p, hcur => by
    have hi : cs[i]? = some c := by have := hat 0; simpa only [List.getElem?_cons_zero,
      Nat.add_zero] using this.symm
    have hlen' : (i + 1) + rest.length = cs.length := by
      simp only [List.length_cons] at hlen; omega
    have hat' : ∀ k, rest[k]? = cs[i + 1 + k]? := fun k => by
      have := hat (k + 1)
      simp only [List.getElem?_cons_succ] at this
      rw [this]; congr 1; omega
    simp only [wordsFrom]
    split
    · next hb =>
      have hsp : cs[i]? = some ' ' := by
        rw [hi]; simp only [isBreak, beq_iff_eq] at hb; rw [hb]
      cases cur with
      | none =>
        obtain ⟨h1, h2⟩ := hcur
        refine wordsFrom_cover cs rest (i + 1) hlen' hat' none p ⟨by omega, fun k hk hk' => ?_⟩
        rcases Nat.lt_or_eq_of_le (Nat.le_of_lt_succ hk') with h | h
        · exact h2 k hk h
        · subst h; exact hsp
      | some a =>
        obtain ⟨h1, h2, h3⟩ := hcur
        refine .cons h1 h2 h3 ?_
        refine wordsFrom_cover cs rest (i + 1) hlen' hat' none i ⟨by omega, fun k hk hk' => ?_⟩
        have : k = i := by omega
        subst this; exact hsp
    · cases cur with
      | none =>
        obtain ⟨h1, h2⟩ := hcur
        exact wordsFrom_cover cs rest (i + 1) hlen' hat' (some i) p ⟨h1, by omega, h2⟩
      | some a =>
        obtain ⟨h1, h2, h3⟩ := hcur
        exact wordsFrom_cover cs rest (i + 1) hlen' hat' (some a) p ⟨h1, by omega, h3⟩

theorem words_cover (cs : List Char) :
    Cover (fun k => cs[k]? = some ' ') cs.length 0 (words cs) :=
  wordsFrom_cover cs cs 0 (by omega) (fun k => by rw [Nat.zero_add]) none 0
    ⟨Nat.le_refl _, fun k h1 h2 => by omega⟩

theorem chunkGo_cover {sp : Nat → Prop} {len : Nat} (o : Nat → Int) (W : Int) (b : Nat)
    (rs : List (Nat × Nat)) :
    ∀ (fuel a p : Nat), Cover sp len p ((a, b) :: rs) →
      Cover sp len p ((chunkGo o W b fuel a).1 ++ (chunkGo o W b fuel a).2 :: rs)
  | 0, a, p, h => by simpa only [chunkGo, List.nil_append] using h
  | fuel + 1, a, p, h => by
    simp only [chunkGo]
    split
    · simpa only [List.nil_append] using h
    · next hbc =>
      cases h with
      | cons h1 h2 h3 h4 =>
        have hc := (cut_spec o W a b).2.1
        simp only [List.cons_append]
        refine .cons h1 (by omega) h3 ?_
        exact chunkGo_cover o W b rs fuel _ _
          (.cons (Nat.le_refl _) (by omega) (fun i h h' => by omega) h4)

theorem chunk_cover {sp : Nat → Prop} {len : Nat} (o : Nat → Int) (W : Int) (w : Nat × Nat)
    (rs : List (Nat × Nat)) {p : Nat} (h : Cover sp len p (w :: rs)) :
    Cover sp len p ((chunk o W w).1 ++ (chunk o W w).2 :: rs) :=
  chunkGo_cover o W w.2 rs (w.2 - w.1) w.1 p h

/-- Replacing what follows a prefix keeps a cover, if it keeps the cover from where the prefix
ends. -/
theorem Cover.append {sp : Nat → Prop} {len : Nat} {x : Nat × Nat} {ws F : List (Nat × Nat)}
    (hF : ∀ q, Cover sp len q (x :: ws) → Cover sp len q F) :
    ∀ (pre : List (Nat × Nat)) (p : Nat), Cover sp len p (pre ++ x :: ws) →
      Cover sp len p (pre ++ F)
  | [], p, h => hF p h
  | y :: pre, p, h => by
    cases h with
    | cons h1 h2 h3 h4 => exact .cons h1 h2 h3 (Cover.append hF pre _ h4)

theorem Cover.merge {sp : Nat → Prop} {len p a b c d : Nat} {rs : List (Nat × Nat)}
    (h : Cover sp len p ((a, b) :: (c, d) :: rs)) : Cover sp len p ((a, d) :: rs) := by
  cases h with
  | cons h1 h2 h3 h4 =>
    cases h4 with
    | cons h5 h6 _ h8 => exact .cons h1 (by omega) h3 h8

theorem fill_cover {sp : Nat → Prop} {len : Nat} (o : Nat → Int) (W : Int) :
    ∀ (ws : List (Nat × Nat)) (cur : Nat × Nat) (p : Nat),
      Cover sp len p (cur :: ws) → Cover sp len p (fill o W cur ws)
  | [], cur, p, h => by simpa only [fill] using h
  | w :: ws, cur, p, h => by
    simp only [fill]
    split
    · exact fill_cover o W ws _ p (Cover.merge h)
    · cases h with
      | cons h1 h2 h3 h4 =>
        exact .cons h1 h2 h3 (Cover.append (fun q hq => fill_cover o W ws _ q hq) _ _
          (chunk_cover o W w ws h4))

theorem breakAll_cover {sp : Nat → Prop} {len : Nat} (o : Nat → Int) (W : Int) {p : Nat} :
    ∀ {ws : List (Nat × Nat)}, Cover sp len p ws → Cover sp len p (breakAll o W ws)
  | [], h => h
  | w :: ws, h => Cover.append (fun q hq => fill_cover o W ws _ q hq) _ _ (chunk_cover o W w ws h)

/-- **Lines cover the text.** The lines are nonempty, in order, within the text, and every
scalar outside them is a break space. -/
theorem allLines_cover (o : Nat → Int) (W : Int) (cs : List Char) :
    Cover (fun k => cs[k]? = some ' ') cs.length 0 (allLines o W cs) :=
  breakAll_cover o W (words_cover cs)

/-- `Tiles cs ls`: `cs = g₀ ++ l₀ ++ g₁ ++ l₁ ++ … ++ lₖ ++ gₖ₊₁` where `ls = [l₀, …, lₖ]`, every
line is nonempty and every gap is break spaces. -/
inductive Tiles : List Char → List (List Char) → Prop
  | last {g : List Char} : (∀ c ∈ g, c = ' ') → Tiles g []
  | line {g l rest : List Char} {ls : List (List Char)} : (∀ c ∈ g, c = ' ') → l ≠ [] →
      Tiles rest ls → Tiles (g ++ l ++ rest) (l :: ls)

theorem spaces_of_gap {cs : List Char} {p q : Nat}
    (h : ∀ i, p ≤ i → i < q → cs[i]? = some ' ') : ∀ c ∈ (cs.drop p).take (q - p), c = ' ' := by
  intro c hc
  obtain ⟨k, hk, hkc⟩ := List.getElem_of_mem hc
  have hk' : k < q - p := by simp only [List.length_take] at hk; omega
  have : cs[p + k]? = some c := by
    rw [← List.getElem?_drop, ← List.getElem?_take_of_lt hk', List.getElem?_eq_getElem hk, hkc]
  rw [h (p + k) (by omega) (by omega)] at this
  exact (Option.some.inj this).symm

theorem Cover.tiles {cs : List Char} {p : Nat} {rs : List (Nat × Nat)}
    (h : Cover (fun k => cs[k]? = some ' ') cs.length p rs) :
    Tiles (cs.drop p) (rs.map (slice cs)) := by
  induction h with
  | @nil p h1 h2 =>
    refine .last ?_
    have := spaces_of_gap (cs := cs) (p := p) (q := cs.length) h2
    rwa [List.take_of_length_le (by simp only [List.length_drop]; omega)] at this
  | @cons p a b rs h1 h2 h3 h4 ih =>
    have hb := h4.le
    have e1 : cs.drop p = (cs.drop p).take (a - p) ++ cs.drop a := by
      conv => lhs; rw [← List.take_append_drop (a - p) (cs.drop p)]
      rw [List.drop_drop]; congr 2; omega
    have e2 : cs.drop a = slice cs (a, b) ++ cs.drop b := by
      simp only [slice]
      conv => lhs; rw [← List.take_append_drop (b - a) (cs.drop a)]
      rw [List.drop_drop]; congr 2; omega
    rw [e1, e2, List.map_cons, ← List.append_assoc]
    refine .line (spaces_of_gap h3) ?_ ih
    intro he
    have := congrArg List.length he
    simp only [slice, List.length_take, List.length_drop, List.length_nil] at this
    omega

/-- **Lines tile the text.** Put back between and around the lines, break spaces alone rebuild
the text. -/
theorem allLines_tiles (o : Nat → Int) (W : Int) (cs : List Char) :
    Tiles cs ((allLines o W cs).map (slice cs)) := by
  simpa only [List.drop_zero] using (allLines_cover o W cs).tiles

/-! ## Line count and which lines are kept -/

theorem keepLines_length_le {α : Type} (n : Nat) (k : Keep) (ls : List α) :
    (keepLines (some n) k ls).length ≤ n := by
  cases k <;> simp only [keepLines, List.length_take, List.length_drop] <;> omega

/-- **Line count.** At most `maxLines` lines. -/
theorem lines_length_le (o : Nat → Int) (W : Int) (wr : Wrap) (cs : List Char) (n : Nat)
    (h : wr.maxLines = some n) : (lines o W wr cs).length ≤ n := by
  simp only [lines, h]; exact keepLines_length_le n _ _

/-- **Keep tail.** The lines shown are exactly the last `min n k` of all `k` lines. -/
theorem lines_tail (o : Nat → Int) (W : Int) (wr : Wrap) (cs : List Char) (n : Nat)
    (hm : wr.maxLines = some n) (hk : wr.keep = .tail) :
    ∃ pre, pre ++ lines o W wr cs = allLines o W cs ∧
      (lines o W wr cs).length = min n (allLines o W cs).length := by
  simp only [lines, hm, hk, keepLines]
  refine ⟨(allLines o W cs).take ((allLines o W cs).length - n), List.take_append_drop _ _, ?_⟩
  simp only [List.length_drop]; omega

/-- **Keep head.** The lines shown are exactly the first `min n k`. -/
theorem lines_head (o : Nat → Int) (W : Int) (wr : Wrap) (cs : List Char) (n : Nat)
    (hm : wr.maxLines = some n) (hk : wr.keep = .head) :
    ∃ post, lines o W wr cs ++ post = allLines o W cs ∧
      (lines o W wr cs).length = min n (allLines o W cs).length := by
  simp only [lines, hm, hk, keepLines]
  exact ⟨_, List.take_append_drop _ _, by simp only [List.length_take]⟩

/-- Without `maxLines`, every line is shown. -/
theorem lines_none (o : Nat → Int) (W : Int) (wr : Wrap) (cs : List Char)
    (hm : wr.maxLines = none) : lines o W wr cs = allLines o W cs := by
  simp only [lines, hm, keepLines]

/-- Every line shown is one of the lines, so it fits. -/
theorem mem_lines (o : Nat → Int) (W : Int) (wr : Wrap) (cs : List Char) {l : Nat × Nat}
    (h : l ∈ lines o W wr cs) : l ∈ allLines o W cs := by
  simp only [lines] at h
  rcases hm : wr.maxLines with _ | n <;> rw [hm] at h
  · exact h
  · cases hk : wr.keep <;> rw [hk] at h <;> simp only [keepLines] at h
    · exact List.mem_of_mem_take h
    · exact List.mem_of_mem_drop h

theorem lines_fit (o : Nat → Int) (W : Int) (wr : Wrap) (cs : List Char) :
    ∀ l ∈ lines o W wr cs, o l.2 - o l.1 ≤ W ∨ l.2 ≤ l.1 + 1 :=
  fun l h => allLines_fit o W cs l (mem_lines o W wr cs h)

/-! ## Examples, one scalar per point -/

private def unit (i : Nat) : Int := i

#guard words "  ab cd  e ".toList == [(2, 4), (5, 7), (9, 10)]
#guard allLines unit 5 "ab cd ef".toList == [(0, 5), (6, 8)]
#guard (allLines unit 5 "ab cd ef".toList).map (fun p => String.ofList (slice "ab cd ef".toList p))
  == ["ab cd", "ef"]
-- A word wider than the line is cut into pieces that fit.
#guard allLines unit 3 "abcdefg h".toList == [(0, 3), (3, 6), (6, 9)]
-- An over-wide word starts a new line before it is cut.
#guard allLines unit 4 "a bcdefg".toList == [(0, 1), (2, 6), (6, 8)]
#guard allLines unit 4 "ab cdefghij".toList == [(0, 2), (3, 7), (7, 11)]
-- At width 0 every line is one scalar.
#guard allLines unit 0 "ab c".toList == [(0, 1), (1, 2), (3, 4)]
#guard allLines unit 10 "    ".toList == []
#guard lines unit 2 { maxLines := some 2, keep := .tail } "a b c d".toList == [(4, 5), (6, 7)]
#guard lines unit 2 { maxLines := some 2 } "a b c d".toList == [(0, 1), (2, 3)]

end Cairn.Text.Wrap
