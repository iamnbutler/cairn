module

public import Cairn.UI.Node

/-! # Line breaking

Lean decides where wrapped text (`Node.para`) breaks; the host only measures. Everything here
works on the text as a list of Unicode scalars and on its caret offsets `o : Nat → Int` (`o i`
is the x offset before scalar `i`, from one Core Text shaping of the whole string, so a line
`[a, b)` is `o b - o a` wide). The rules (`docs/layout.md`, "Wrapped text"):

1. **Words** are maximal runs of scalars other than the *break space* U+0020 (`isBreak`). Lines
   break only between words, and the spaces at a break are dropped: a line runs from the start
   of its first word to the end of its last, with the spaces between its own words kept.
2. **Over-wide words.** A word wider than the width is cut into *pieces* (`chunk`): each the
   longest run of its scalars, from where the last one ended, that fits, and never less than one
   scalar. A word that fits is one piece. Pieces flow like words, with nothing between them.
3. **Greedy fill** (`fill`): a line takes pieces while the line, measured from its first scalar
   to the end of the next piece, still fits; then the next piece starts a new line.
4. **At most `maxLines`**, keeping the first (`Keep.head`) or the last (`Keep.tail`) lines.

Theorems (`Cairn.Text.WrapProofs`): every line fits the width or is a single scalar; the lines
tile the text with only break spaces between and around them; the count is at most `maxLines`;
`tail` keeps exactly the last lines and `head` the first.

Each function is structural recursion (fuel where the measure isn't), so `#guard` and `decide`
evaluate it; the examples are in `Cairn.Text.WrapProofs`. -/

@[expose] public section

namespace Cairn.Text.Wrap

/-- The break space: the only scalar a line breaks at, and the only one a break drops. -/
def isBreak (c : Char) : Bool := c == ' '

/-- Maximal runs of non-break scalars, as `[a, b)` ranges. `i` is the index of the list's head
in the whole text; `cur` is where the run in progress started, if one is. -/
def wordsFrom : List Char → Nat → Option Nat → List (Nat × Nat)
  | [], _, none => []
  | [], i, some a => [(a, i)]
  | c :: cs, i, cur =>
    if isBreak c then
      match cur with
      | none => wordsFrom cs (i + 1) none
      | some a => (a, i) :: wordsFrom cs (i + 1) none
    else wordsFrom cs (i + 1) (some (cur.getD i))

/-- The words of a text. -/
def words (cs : List Char) : List (Nat × Nat) := wordsFrom cs 0 none

/-- The width of the scalars `[a, b)`. -/
def width (o : Nat → Int) (p : Nat × Nat) : Int := o p.2 - o p.1

/-- From a piece `[a, c)` that is allowed, add scalars while `c < b` and `[a, c + 1)` fits. -/
def cutGo (o : Nat → Int) (W : Int) (a b : Nat) : Nat → Nat → Nat
  | 0, c => c
  | fuel + 1, c => if c < b ∧ o (c + 1) - o a ≤ W then cutGo o W a b fuel (c + 1) else c

/-- Where the piece of `[a, b)` that starts at `a` ends: the longest prefix that fits, and at
least one scalar. -/
def cut (o : Nat → Int) (W : Int) (a b : Nat) : Nat := cutGo o W a b (b - a) (a + 1)

/-- Cut the rest of a word, `[a, b)`, into pieces. `fuel ≥ b - a` suffices. -/
def chunkGo (o : Nat → Int) (W : Int) (b : Nat) : Nat → Nat → List (Nat × Nat)
  | 0, a => [(a, b)]
  | fuel + 1, a =>
    let c := cut o W a b
    if b ≤ c then [(a, b)] else (a, c) :: chunkGo o W b fuel c

/-- A word as pieces: itself if it fits, otherwise cut (rule 2). -/
def chunk (o : Nat → Int) (W : Int) (p : Nat × Nat) : List (Nat × Nat) :=
  chunkGo o W p.2 (p.2 - p.1) p.1

def pieces (o : Nat → Int) (W : Int) (ws : List (Nat × Nat)) : List (Nat × Nat) :=
  ws.flatMap (chunk o W)

/-- Greedy fill: `cur` is the line so far. -/
def fill (o : Nat → Int) (W : Int) : Nat × Nat → List (Nat × Nat) → List (Nat × Nat)
  | cur, [] => [cur]
  | cur, p :: ps => if o p.2 - o cur.1 ≤ W then fill o W (cur.1, p.2) ps else cur :: fill o W p ps

def breakAll (o : Nat → Int) (W : Int) : List (Nat × Nat) → List (Nat × Nat)
  | [] => []
  | p :: ps => fill o W p ps

/-- Every line of `cs` at width `W`, as `[a, b)` scalar ranges, before `maxLines`. -/
def allLines (o : Nat → Int) (W : Int) (cs : List Char) : List (Nat × Nat) :=
  breakAll o W (pieces o W (words cs))

/-- At most `n` lines, from the front or the back. -/
def keepLines {α : Type} : Option Nat → Keep → List α → List α
  | none, _, ls => ls
  | some n, .head, ls => ls.take n
  | some n, .tail, ls => ls.drop (ls.length - n)

/-- The lines a wrapped text shows. -/
def lines (o : Nat → Int) (W : Int) (wr : Wrap) (cs : List Char) : List (Nat × Nat) :=
  keepLines wr.maxLines wr.keep (allLines o W cs)

/-- The scalars of the range `[a, b)`. -/
def slice (cs : List Char) (p : Nat × Nat) : List Char := (cs.drop p.1).take (p.2 - p.1)

end Cairn.Text.Wrap
