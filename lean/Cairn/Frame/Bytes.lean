/-! The byte layer of the boundary format (docs/frame.md): little-endian primitives, three ways.

* `Enc.*` encode to `List UInt8`. They are the specification: short, and what the round-trip
  theorems talk about.
* `Dec` is a decoder over `List UInt8` (consume a prefix, return the value and the rest). Each
  primitive has a round-trip lemma of the form `d (Enc.x v ++ rest) = some (v, rest)`, which is
  what makes the whole-frame theorems compose.
* `Put.*` append to a `ByteArray`. They are what runs; `Put.x_data` says each one appends exactly
  `Enc.x` to the buffer's bytes.

Integers that cross the boundary are 32-bit: `Int` as two's complement (`i32`), `Nat` as
unsigned (`u32`). The round trip needs the value to fit, stated with `FitsI32` and `FitsU32`. -/

namespace Cairn.Wire

/-! ## Ranges -/

def FitsU32 (n : Nat) : Prop := n < 4294967296
def FitsI32 (v : Int) : Prop := -2147483648 ≤ v ∧ v < 2147483648
/-- A string whose UTF-8 encoding has a `u32` length. -/
def FitsStr (s : String) : Prop := s.toUTF8.size < 4294967296

instance (n : Nat) : Decidable (FitsU32 n) := inferInstanceAs (Decidable (_ < _))
instance (v : Int) : Decidable (FitsI32 v) := inferInstanceAs (Decidable (_ ∧ _))
instance (s : String) : Decidable (FitsStr s) := inferInstanceAs (Decidable (_ < _))

/-- Two's complement, as an unsigned 32-bit value. -/
def toU32 (v : Int) : Nat := (v % 4294967296).toNat
def ofU32 (n : Nat) : Int := if n < 2147483648 then n else (n : Int) - 4294967296

@[simp] theorem fitsU32_zero : FitsU32 0 := by decide

theorem toU32_fits (v : Int) : FitsU32 (toU32 v) := by unfold FitsU32 toU32; omega

theorem ofU32_toU32 {v : Int} (h : FitsI32 v) : ofU32 (toU32 v) = v := by
  unfold FitsI32 at h; unfold ofU32 toU32; split <;> omega

def ofBytes (a b c d : UInt8) : Nat :=
  a.toNat + 256 * b.toNat + 65536 * c.toNat + 16777216 * d.toNat

theorem ofBytes_lt (a b c d : UInt8) : ofBytes a b c d < 4294967296 := by
  have := a.toNat_lt; have := b.toNat_lt; have := c.toNat_lt; have := d.toNat_lt
  unfold ofBytes; omega

/-! ## Encoding (specification) -/

namespace Enc

def u32 (n : Nat) : List UInt8 :=
  [UInt8.ofNat n, UInt8.ofNat (n / 256), UInt8.ofNat (n / 65536), UInt8.ofNat (n / 16777216)]

def i32 (v : Int) : List UInt8 := u32 (toU32 v)

def bool (b : Bool) : List UInt8 := [if b then 1 else 0]

/-- `u32` byte length, then the UTF-8 bytes. -/
def str (s : String) : List UInt8 := u32 s.toUTF8.size ++ s.toUTF8.data.toList

/-- Reserved bytes: written as zero, ignored when read. -/
def pad (n : Nat) : List UInt8 := List.replicate n 0

/-- A sized section: `u32` byte length, then the body. -/
def sect (body : List UInt8) : List UInt8 := u32 body.length ++ body

@[simp] theorem length_u32 (n : Nat) : (u32 n).length = 4 := rfl
@[simp] theorem length_i32 (v : Int) : (i32 v).length = 4 := rfl

end Enc

/-! ## Decoding -/

/-- Consume a prefix of the input; `none` is a decoding error. -/
def Dec (α : Type) : Type := List UInt8 → Option (α × List UInt8)

namespace Dec

variable {α β : Type}

@[inline] protected def pure (a : α) : Dec α := fun l => some (a, l)

@[inline] protected def bind (d : Dec α) (f : α → Dec β) : Dec β := fun l =>
  match d l with
  | some (a, r) => f a r
  | none => none

instance : Monad Dec where
  pure := Dec.pure
  bind := Dec.bind

def fail : Dec α := fun _ => none

@[simp] theorem pure_apply (a : α) (l : List UInt8) : (pure a : Dec α) l = some (a, l) := rfl

@[simp] theorem bind_apply (d : Dec α) (f : α → Dec β) (l : List UInt8) :
    (d >>= f) l = (match d l with | some (a, r) => f a r | none => none) := rfl

@[simp] theorem fail_apply (l : List UInt8) : (fail : Dec α) l = none := rfl

/-- The step every compound round-trip proof takes: run the first decoder, continue. -/
theorem bind_of_eq {d : Dec α} {f : α → Dec β} {l r : List UInt8} {a : α}
    (h : d l = some (a, r)) : (d >>= f) l = f a r := by
  simp [h]

def byte : Dec UInt8
  | b :: r => some (b, r)
  | [] => none

def u32 : Dec Nat
  | a :: b :: c :: d :: r => some (ofBytes a b c d, r)
  | _ => none

def i32 : Dec Int := do return ofU32 (← u32)

def bool : Dec Bool := do
  match (← byte) with
  | 0 => return false
  | 1 => return true
  | _ => fail

def take (n : Nat) : Dec (List UInt8) := fun l =>
  if n ≤ l.length then some (l.take n, l.drop n) else none

def skip (n : Nat) : Dec Unit := fun l =>
  if n ≤ l.length then some ((), l.drop n) else none

def str : Dec String := do
  let n ← u32
  let bs ← take n
  match String.fromUTF8? ⟨bs.toArray⟩ with
  | some s => return s
  | none => fail

/-- `n` values, one after another. -/
def count (d : Dec α) : Nat → Dec (List α)
  | 0 => pure []
  | n + 1 => do
    let a ← d
    let as ← count d n
    return a :: as

/-- A sized section: read the `u32` byte length, decode the body with `d`, which must consume
it exactly. -/
def sect (d : Dec α) : Dec α := do
  let n ← u32
  let body ← take n
  match d body with
  | some (a, []) => return a
  | _ => fail

/-- Decode all of `l`; trailing bytes are an error. -/
def run (d : Dec α) (l : List UInt8) : Option α :=
  match d l with
  | some (a, []) => some a
  | _ => none

/-! ### Round trips of the primitives -/

@[simp] theorem byte_cons (b : UInt8) (r : List UInt8) : byte (b :: r) = some (b, r) := rfl

theorem u32_enc {n : Nat} (h : FitsU32 n) (r : List UInt8) :
    u32 (Enc.u32 n ++ r) = some (n, r) := by
  unfold FitsU32 at h
  simp only [u32, Enc.u32, List.cons_append, List.nil_append, Option.some.injEq, Prod.mk.injEq,
    and_true]
  simp only [ofBytes, UInt8.toNat_ofNat', Nat.reducePow]
  omega

theorem i32_enc {v : Int} (h : FitsI32 v) (r : List UInt8) :
    i32 (Enc.i32 v ++ r) = some (v, r) := by
  simp [i32, Enc.i32, u32_enc (toU32_fits v), ofU32_toU32 h]

theorem bool_enc (b : Bool) (r : List UInt8) : bool (Enc.bool b ++ r) = some (b, r) := by
  cases b <;> rfl

theorem take_enc (l r : List UInt8) : take l.length (l ++ r) = some (l, r) := by
  simp [take]

theorem skip_pad (n : Nat) (r : List UInt8) : skip n (Enc.pad n ++ r) = some ((), r) := by
  simp [skip, Enc.pad]

theorem fromUTF8?_toUTF8 (s : String) :
    String.fromUTF8? ⟨s.toUTF8.data.toList.toArray⟩ = some s := by
  simp only [Array.toArray_toList]
  simp [String.fromUTF8?, String.fromUTF8, String.toUTF8, s.isValidUTF8]

theorem str_enc {s : String} (h : FitsStr s) (r : List UInt8) :
    str (Enc.str s ++ r) = some (s, r) := by
  have hl : s.toUTF8.data.toList.length = s.toUTF8.size := by simp
  simp only [str, Enc.str, List.append_assoc, bind_apply, u32_enc h]
  rw [← hl, take_enc]
  dsimp only
  rw [fromUTF8?_toUTF8]
  rfl

theorem count_enc {d : Dec α} {e : α → List UInt8} (xs : List α)
    (h : ∀ x ∈ xs, ∀ r, d (e x ++ r) = some (x, r)) (r : List UInt8) :
    count d xs.length (xs.flatMap e ++ r) = some (xs, r) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    simp only [List.length_cons, count, List.flatMap_cons, List.append_assoc, bind_apply,
      h x List.mem_cons_self]
    simp [ih (fun y hy => h y (List.mem_cons_of_mem _ hy))]

theorem sect_enc {d : Dec α} {body : List UInt8} {a : α} (hd : d body = some (a, []))
    (hn : FitsU32 body.length) (r : List UInt8) :
    sect d (Enc.sect body ++ r) = some (a, r) := by
  simp only [sect, Enc.sect, List.append_assoc, bind_apply, u32_enc hn, take_enc, hd]
  rfl

theorem run_enc {d : Dec α} {l : List UInt8} {a : α} (h : d (l ++ []) = some (a, [])) :
    run d l = some a := by
  simp only [List.append_nil] at h
  simp [run, h]

end Dec

/-! ## Executable encoders on `ByteArray` -/

namespace Put

@[inline] def u8 (b : ByteArray) (v : UInt8) : ByteArray := b.push v

@[inline] def u32 (b : ByteArray) (n : Nat) : ByteArray :=
  (((b.push (UInt8.ofNat n)).push (UInt8.ofNat (n / 256))).push
    (UInt8.ofNat (n / 65536))).push (UInt8.ofNat (n / 16777216))

@[inline] def i32 (b : ByteArray) (v : Int) : ByteArray := u32 b (toU32 v)

@[inline] def bool (b : ByteArray) (v : Bool) : ByteArray := b.push (if v then 1 else 0)

@[inline] def str (b : ByteArray) (s : String) : ByteArray := u32 b s.toUTF8.size ++ s.toUTF8

@[inline] def pad (b : ByteArray) : Nat → ByteArray
  | 0 => b
  | n + 1 => pad (b.push 0) n

/-- Overwrite the four bytes at `i` with `n` (for a section length, once the body is known). -/
@[inline] def setU32 (b : ByteArray) (i n : Nat) : ByteArray :=
  (((b.set! i (UInt8.ofNat n)).set! (i + 1) (UInt8.ofNat (n / 256))).set! (i + 2)
    (UInt8.ofNat (n / 65536))).set! (i + 3) (UInt8.ofNat (n / 16777216))

@[simp] theorem u8_data (b : ByteArray) (v : UInt8) :
    (u8 b v).data.toList = b.data.toList ++ [v] := by
  simp [u8]

@[simp] theorem u32_data (b : ByteArray) (n : Nat) :
    (u32 b n).data.toList = b.data.toList ++ Enc.u32 n := by
  simp [u32, Enc.u32]

@[simp] theorem i32_data (b : ByteArray) (v : Int) :
    (i32 b v).data.toList = b.data.toList ++ Enc.i32 v := by
  simp [i32, Enc.i32]

@[simp] theorem bool_data (b : ByteArray) (v : Bool) :
    (bool b v).data.toList = b.data.toList ++ Enc.bool v := by
  simp [bool, Enc.bool]

@[simp] theorem str_data (b : ByteArray) (s : String) :
    (str b s).data.toList = b.data.toList ++ Enc.str s := by
  simp [str, Enc.str]

@[simp] theorem pad_data (b : ByteArray) (n : Nat) :
    (pad b n).data.toList = b.data.toList ++ Enc.pad n := by
  induction n generalizing b with
  | zero => simp [pad, Enc.pad]
  | succ n ih => simp [pad, ih, Enc.pad, List.replicate_succ]

end Put

end Cairn.Wire
