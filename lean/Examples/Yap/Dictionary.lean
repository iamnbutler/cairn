module

public import Examples.Yap.Graphemes
public import Examples.Yap.Fold

/-! # Yap: the dictionary

Mirrors `DictationDictionary.swift` (Yap's `Packages/Core`): `dictionary.txt` holds terms, sent
to the model as vocabulary (only the first 25), and fixes, `heard => written`, applied to the
transcript afterwards, whole words only, in any case.

Everything works on `List Char`, so the proofs are about lists. `Replaces` says what one fix
may do to a text: copy it, except that some case-insensitive occurrences of `heard` with no
word character on either side become `written`. `replaceWord_replaces` proves the
implementation stays inside that, for every fix and text: a fix never rewrites part of a word.

Matching is ICU's: full case folding, and `[\w-]` from ICU's own tables (`Examples.Yap.Fold`). -/

@[expose] public section

namespace Examples.Yap

/-- Swift's `CharacterSet.whitespaces`: tab, the Unicode space separators, and U+200B (read
off `CharacterSet.whitespaces.contains` for every scalar). -/
def isSpace (c : Char) : Bool :=
  c == ' ' || c == '\t' || c.val == 0xA0 || c.val == 0x1680 ||
    (0x2000 ≤ c.val && c.val ≤ 0x200B) || c.val == 0x202F || c.val == 0x205F || c.val == 0x3000

/-- Swift's `Character.isNewline`. -/
def isNewline (c : Char) : Bool :=
  c == '\n' || c == '\r' || c.val == 0x0B || c.val == 0x0C || c.val == 0x85 ||
    c.val == 0x2028 || c.val == 0x2029

/-- A character the fix pattern's `(?<![\w-])` and `(?![\w-])` refuse next to a match: what
ICU's `[\w-]` matches. -/
def isWordChar (c : Char) : Bool := Fold.isWord c

/-- Case-insensitive equality as ICU's matcher has it: the same full case folding. -/
def sameFold (a b : List Char) : Bool := a.flatMap Fold.fold == b.flatMap Fold.fold

/-- How many characters at the front of `xs` match `h` case-insensitively (0 for none): at most
as many as `h` folds to, as each character folds to at least one. -/
def spanLen (h xs : List Char) : Nat :=
  ((List.range ((h.flatMap Fold.fold).length + 1)).find? fun n =>
    n ≠ 0 && n ≤ xs.length && sameFold (xs.take n) h).getD 0

theorem spanLen_fold {h xs : List Char} (hn : 0 < spanLen h xs) :
    sameFold (xs.take (spanLen h xs)) h = true := by
  unfold spanLen at hn ⊢
  cases hf : (List.range ((h.flatMap Fold.fold).length + 1)).find? (fun n =>
      n ≠ 0 && n ≤ xs.length && sameFold (xs.take n) h) with
  | none => rw [hf] at hn; simp at hn
  | some n =>
    have := List.find?_some hf
    simp only [Bool.and_eq_true, decide_eq_true_eq] at this
    exact this.2

/-- No word character just before. -/
def boundaryBefore : Option Char → Bool
  | none => true
  | some c => !isWordChar c

/-- No word character just after. -/
def boundaryAfter : List Char → Bool
  | [] => true
  | c :: _ => !isWordChar c

def trimBy (p : Char → Bool) (cs : List Char) : List Char :=
  ((cs.dropWhile p).reverse.dropWhile p).reverse

/-- `trimmingCharacters(in: .whitespacesAndNewlines)`. -/
def trimText (s : String) : String :=
  String.ofList (trimBy (fun c => isSpace c || isNewline c) s.toList)

/-! ## One fix -/

/-- Replace every whole-word, case-insensitive occurrence of `h` in the text with `w`, left to
right, not overlapping, as `NSRegularExpression` does with `(?<![\w-])h(?![\w-])`. `prev` is
the character before the text (the lookbehind sees the original text, not the replacement). -/
def replaceWord (h w : List Char) (prev : Option Char) : List Char → List Char
  | [] => []
  | c :: cs =>
    if 0 < spanLen h (c :: cs) ∧ boundaryBefore prev = true ∧
        boundaryAfter ((c :: cs).drop (spanLen h (c :: cs))) = true then
      w ++ replaceWord h w ((c :: cs).take (spanLen h (c :: cs))).getLast?
        ((c :: cs).drop (spanLen h (c :: cs)))
    else c :: replaceWord h w (some c) cs
termination_by xs => xs.length
decreasing_by
  all_goals simp_wf
  · rename_i hc
    have := hc.1
    omega

/-- **What a fix may do.** The output copies the input, except that some spans are replaced by
`w`; each such span is `h` up to case (the same full case folding), and has no word character
on either side in the input. -/
inductive Replaces (h w : List Char) : Option Char → List Char → List Char → Prop
  | nil (prev : Option Char) : Replaces h w prev [] []
  | keep (prev : Option Char) (c : Char) (cs out : List Char) :
      Replaces h w (some c) cs out → Replaces h w prev (c :: cs) (c :: out)
  | swap (prev : Option Char) (span rest out : List Char) :
      span ≠ [] → sameFold span h = true → boundaryBefore prev = true →
      boundaryAfter rest = true → Replaces h w span.getLast? rest out →
      Replaces h w prev (span ++ rest) (w ++ out)

theorem take_ne_nil {α : Type} {n : Nat} {l : List α} (hn : 0 < n) (hl : l ≠ []) :
    l.take n ≠ [] := by
  cases l with
  | nil => exact absurd rfl hl
  | cons a t => cases n with
    | zero => omega
    | succ n => simp

/-- **Fixes replace whole words only**: for every fix and every text, `replaceWord` is one of
the rewrites `Replaces` allows. -/
theorem replaceWord_replaces (h w : List Char) (prev : Option Char) (xs : List Char) :
    Replaces h w prev xs (replaceWord h w prev xs) := by
  induction prev, xs using replaceWord.induct h with
  | case1 prev => rw [replaceWord]; exact .nil prev
  | case2 prev c cs hc ih =>
    rw [replaceWord, ite_eq_left hc]
    obtain ⟨hne, hb, ha⟩ := hc
    have hspan : (c :: cs).take (spanLen h (c :: cs)) ≠ [] :=
      take_ne_nil hne (List.cons_ne_nil c cs)
    have := Replaces.swap prev _ _ _ hspan (spanLen_fold hne) hb ha ih
    rwa [List.take_append_drop] at this
  | case3 prev c cs hc ih =>
    rw [replaceWord, ite_eq_right hc]
    exact .keep prev c cs _ ih

/-! ## The dictionary -/

/-- One fix, `heard => written`. -/
structure Fix where
  heard : String
  written : String
deriving Repr, DecidableEq, Inhabited

structure Dictionary where
  terms : List String := []
  fixes : List Fix := []
deriving Repr, DecidableEq, Inhabited

/-- Only this many terms are sent: more vocabulary measured worse (Yap's README). -/
def promptLimit : Nat := 25

def Fix.apply (f : Fix) (text : String) : String :=
  String.ofList (replaceWord f.heard.toList f.written.toList none text.toList)

/-- Every fix, in order, each on the previous one's output (`fixes.reduce` in Swift). -/
def applyFixes (fixes : List Fix) (text : String) : String :=
  fixes.foldl (fun t f => f.apply t) text

/-- What a transcript becomes before it is typed: the fixes, then trimmed. -/
def fixText (fixes : List Fix) (raw : String) : String := trimText (applyFixes fixes raw)

/-- A chain of fixes, each allowed by `Replaces`. -/
inductive ReplacesAll : List Fix → List Char → List Char → Prop
  | nil (xs : List Char) : ReplacesAll [] xs xs
  | cons (f : Fix) (fs : List Fix) (xs ys zs : List Char) :
      Replaces f.heard.toList f.written.toList none xs ys → ReplacesAll fs ys zs →
      ReplacesAll (f :: fs) xs zs

theorem applyFixes_replacesAll (fs : List Fix) (text : String) :
    ReplacesAll fs text.toList (applyFixes fs text).toList := by
  induction fs generalizing text with
  | nil => exact .nil _
  | cons f fs ih =>
    simp only [applyFixes, List.foldl_cons] at ih ⊢
    exact .cons f fs _ _ _ (by simpa [Fix.apply] using replaceWord_replaces _ _ none _) (ih _)

/-- The vocabulary prompt for these terms; none without terms, so the request leaves the
field out. -/
def vocabPrompt (terms : List String) : Option String :=
  if terms.isEmpty then none
  else some ("Dictated into a Claude Code terminal session. Vocabulary: " ++
    ", ".intercalate terms ++ ".")

/-- The prompt for a request: the vocabulary (the first 25 terms), then the context a preview
chunk carries, if any (`Yap.livePrompt`). -/
def Dictionary.promptFor (d : Dictionary) (context : Option String) : Option String :=
  match context with
  | none => vocabPrompt (d.terms.take promptLimit)
  | some c => some (match vocabPrompt (d.terms.take promptLimit) with
    | none => c
    | some p => p ++ " " ++ c)

/-- **Only the first 25 terms are sent**: the prompt is the same with every later term gone. -/
theorem promptFor_take (d : Dictionary) (context : Option String) :
    d.promptFor context = { d with terms := d.terms.take promptLimit }.promptFor context := by
  simp [Dictionary.promptFor, List.take_take]

/-! ## Parsing `dictionary.txt` -/

/-- Split at every character `p` accepts. -/
def splitWhen (p : Char → Bool) : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    if p c then [] :: splitWhen p cs
    else match splitWhen p cs with
      | [] => [[c]]
      | l :: ls => (c :: l) :: ls

/-- The characters before and after the first `=` `>` pair of characters. -/
def breakArrowAt : List (List Char) → Option (List (List Char) × List (List Char))
  | [] => none
  | ['='] :: ['>'] :: rest => some ([], rest)
  | c :: cs => (breakArrowAt cs).map fun p => (c :: p.1, p.2)

/-- The text before and after the first `=>` that `range(of: "=>")` finds: one that starts and
ends on character boundaries, so not `=>` with a combining mark on the `>`. -/
def breakArrow (line : List Char) : Option (List Char × List Char) :=
  (breakArrowAt (Graphemes.clusters line)).map fun (a, b) => (a.flatten, b.flatten)

def parseLine (d : Dictionary) (raw : List Char) : Dictionary :=
  let line := trimBy isSpace raw
  -- `hasPrefix("#")` is about characters: `#` with a combining mark isn't a comment.
  if line.isEmpty || (Graphemes.clusters line).head? == some ['#'] then d
  else match breakArrow line with
    | some (h, w) =>
      let h := trimBy isSpace h
      if h.isEmpty then d
      else { d with fixes := d.fixes ++ [⟨String.ofList h, String.ofList (trimBy isSpace w)⟩] }
    | none => { d with terms := d.terms ++ [String.ofList line] }

/-- `DictationDictionary.parse`: one entry per line; blank lines and `#` comments skipped. -/
def Dictionary.parse (text : String) : Dictionary :=
  ((splitWhen isNewline text.toList).filter (!·.isEmpty)).foldl parseLine {}

end Examples.Yap
