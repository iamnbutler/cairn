module

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

@[expose] public section

namespace Cairn.Wire

/-! ## Ranges -/

def FitsU32 (n : Nat) : Prop := n < 4294967296
def FitsI32 (v : Int) : Prop := -2147483648 ≤ v ∧ v < 2147483648
/-- A string whose UTF-8 encoding has a `u32` length. -/
def FitsStr (s : String) : Prop := s.toUTF8.size < 4294967296
def FitsU64 (n : Nat) : Prop := n < 18446744073709551616
def FitsI64 (v : Int) : Prop := -9223372036854775808 ≤ v ∧ v < 9223372036854775808
/-- A byte payload with a `u32` length. -/
def FitsBytes (b : ByteArray) : Prop := b.size < 4294967296

instance (n : Nat) : Decidable (FitsU32 n) := inferInstanceAs (Decidable (_ < _))
instance (v : Int) : Decidable (FitsI32 v) := inferInstanceAs (Decidable (_ ∧ _))
instance (s : String) : Decidable (FitsStr s) := inferInstanceAs (Decidable (_ < _))
instance (n : Nat) : Decidable (FitsU64 n) := inferInstanceAs (Decidable (_ < _))
instance (v : Int) : Decidable (FitsI64 v) := inferInstanceAs (Decidable (_ ∧ _))
instance (b : ByteArray) : Decidable (FitsBytes b) := inferInstanceAs (Decidable (_ < _))

/-- Two's complement, as an unsigned 32-bit value. -/
def toU32 (v : Int) : Nat := (v % 4294967296).toNat
def ofU32 (n : Nat) : Int := if n < 2147483648 then n else (n : Int) - 4294967296

@[simp] theorem fitsU32_zero : FitsU32 0 := by decide

/-- Two's complement, as an unsigned 64-bit value. -/
def toU64 (v : Int) : Nat := (v % 18446744073709551616).toNat
def ofU64 (n : Nat) : Int :=
  if n < 9223372036854775808 then n else (n : Int) - 18446744073709551616

theorem toU64_fits (v : Int) : FitsU64 (toU64 v) := by unfold FitsU64 toU64; omega

theorem ofU64_toU64 {v : Int} (h : FitsI64 v) : ofU64 (toU64 v) = v := by
  unfold FitsI64 at h; unfold ofU64 toU64; split <;> omega

/-- The two's-complement word of `v`, without big-integer arithmetic: 2³² is not a small number
to Lean's runtime, so `v % 4294967296` (and even the literal) goes through GMP. -/
def i32Word (v : Int) : UInt32 :=
  if 0 ≤ v then UInt32.ofNat v.toNat else 0 - UInt32.ofNat (-v).toNat

theorem i32Word_eq (v : Int) : i32Word v = UInt32.ofNat (toU32 v) := by
  apply UInt32.toNat_inj.mp
  unfold i32Word toU32
  split
  · simp only [UInt32.toNat_ofNat', Nat.reducePow]; omega
  · simp only [UInt32.zero_sub, UInt32.toNat_neg, UInt32.size, UInt32.toNat_ofNat',
      Nat.reducePow]; omega

theorem toU32_fits (v : Int) : FitsU32 (toU32 v) := by unfold FitsU32 toU32; omega

theorem ofU32_toU32 {v : Int} (h : FitsI32 v) : ofU32 (toU32 v) = v := by
  unfold FitsI32 at h; unfold ofU32 toU32; split <;> omega

/-- Clamp to the largest `u32` (font fields cross saturating, docs/frame.md). -/
def satU32 (n : Nat) : Nat := if n < 4294967296 then n else 4294967295

theorem satU32_of_fits {n : Nat} (h : FitsU32 n) : satU32 n = n := by
  unfold FitsU32 at h; simp only [satU32, h, ↓reduceIte]

theorem satU32_fits (n : Nat) : FitsU32 (satU32 n) := by
  unfold satU32 FitsU32; split <;> omega

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

/-- Low word, then high word. -/
def u64 (n : Nat) : List UInt8 := u32 (n % 4294967296) ++ u32 (n / 4294967296)

def i64 (v : Int) : List UInt8 := u64 (toU64 v)

/-- `u32` byte length, then the bytes. -/
def bytes (b : ByteArray) : List UInt8 := u32 b.size ++ b.data.toList

/-- `u32` byte length, then the UTF-8 bytes. -/
def str (s : String) : List UInt8 := u32 s.toUTF8.size ++ s.toUTF8.data.toList

/-- Reserved bytes: written as zero, ignored when read. -/
def pad (n : Nat) : List UInt8 := List.replicate n 0

/-- A sized section: `u32` byte length, then the body. -/
def sect (body : List UInt8) : List UInt8 := u32 body.length ++ body

@[simp] theorem length_u32 (n : Nat) : (u32 n).length = 4 := rfl
@[simp] theorem length_i32 (v : Int) : (i32 v).length = 4 := rfl
@[simp] theorem length_u64 (n : Nat) : (u64 n).length = 8 := rfl
@[simp] theorem length_i64 (v : Int) : (i64 v).length = 8 := rfl

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
  simp only [bind_apply, h]

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

def u64 : Dec Nat := do
  let lo ← u32
  let hi ← u32
  return lo + 4294967296 * hi

def i64 : Dec Int := do return ofU64 (← u64)

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

def bytes : Dec ByteArray := do
  let n ← u32
  let bs ← take n
  return ⟨bs.toArray⟩

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
  simp only [i32, Enc.i32, bind_apply, u32_enc (toU32_fits v), ofU32_toU32 h, pure_apply]

theorem u64_enc {n : Nat} (h : FitsU64 n) (r : List UInt8) :
    u64 (Enc.u64 n ++ r) = some (n, r) := by
  unfold FitsU64 at h
  have h1 : FitsU32 (n % 4294967296) := by unfold FitsU32; omega
  have h2 : FitsU32 (n / 4294967296) := by unfold FitsU32; omega
  simp only [u64, Enc.u64, List.append_assoc, bind_apply, u32_enc h1, u32_enc h2, pure_apply]
  congr 2; omega

theorem i64_enc {v : Int} (h : FitsI64 v) (r : List UInt8) :
    i64 (Enc.i64 v ++ r) = some (v, r) := by
  simp only [i64, Enc.i64, bind_apply, u64_enc (toU64_fits v), ofU64_toU64 h, pure_apply]

theorem bool_enc (b : Bool) (r : List UInt8) : bool (Enc.bool b ++ r) = some (b, r) := by
  cases b <;> rfl

theorem take_enc (l r : List UInt8) : take l.length (l ++ r) = some (l, r) := by
  simp only [take, List.length_append, Nat.le_add_right, ↓reduceIte, List.take_left',
      List.drop_left']

theorem skip_pad (n : Nat) (r : List UInt8) : skip n (Enc.pad n ++ r) = some ((), r) := by
  simp only [skip, Enc.pad, List.length_append, List.length_replicate, Nat.le_add_right, ↓reduceIte,
      List.drop_left']

theorem fromUTF8?_toUTF8 (s : String) :
    String.fromUTF8? ⟨s.toUTF8.data.toList.toArray⟩ = some s := by
  simp only [Array.toArray_toList, String.toUTF8_eq_toByteArray]
  simp only [String.fromUTF8?, s.isValidUTF8, ↓reduceDIte, String.fromUTF8]

theorem str_enc {s : String} (h : FitsStr s) (r : List UInt8) :
    str (Enc.str s ++ r) = some (s, r) := by
  have hl : s.toUTF8.data.toList.length = s.toUTF8.size := by simp only [String.toUTF8_eq_toByteArray,
      Array.length_toList, ByteArray.size_data, String.size_toByteArray]
  simp only [str, Enc.str, List.append_assoc, bind_apply, u32_enc h]
  rw [← hl, take_enc]
  dsimp only
  rw [fromUTF8?_toUTF8]
  rfl

theorem bytes_enc {b : ByteArray} (h : FitsBytes b) (r : List UInt8) :
    bytes (Enc.bytes b ++ r) = some (b, r) := by
  have hl : b.data.toList.length = b.size := by simp only [Array.length_toList, ByteArray.size_data]
  simp only [bytes, Enc.bytes, List.append_assoc, bind_apply, u32_enc h]
  rw [← hl, take_enc]
  simp only [Array.toArray_toList, pure_apply]

theorem count_enc {d : Dec α} {e : α → List UInt8} (xs : List α)
    (h : ∀ x ∈ xs, ∀ r, d (e x ++ r) = some (x, r)) (r : List UInt8) :
    count d xs.length (xs.flatMap e ++ r) = some (xs, r) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    simp only [List.length_cons, count, List.flatMap_cons, List.append_assoc, bind_apply,
      h x List.mem_cons_self]
    simp only [ih (fun y hy => h y (List.mem_cons_of_mem _ hy)), pure_apply]

theorem sect_enc {d : Dec α} {body : List UInt8} {a : α} (hd : d body = some (a, []))
    (hn : FitsU32 body.length) (r : List UInt8) :
    sect d (Enc.sect body ++ r) = some (a, r) := by
  simp only [sect, Enc.sect, List.append_assoc, bind_apply, u32_enc hn, take_enc, hd]
  rfl

theorem run_enc {d : Dec α} {l : List UInt8} {a : α} (h : d (l ++ []) = some (a, [])) :
    run d l = some a := by
  simp only [List.append_nil] at h
  simp only [run, h]

end Dec

/-! ## Executable encoders on `ByteArray` -/

namespace Put

@[inline] def u8 (b : ByteArray) (v : UInt8) : ByteArray := b.push v

/-- A machine word, little-endian, by shifts. -/
@[inline] def word (b : ByteArray) (w : UInt32) : ByteArray :=
  (((b.push w.toUInt8).push (w >>> 8).toUInt8).push (w >>> 16).toUInt8).push (w >>> 24).toUInt8

@[inline] def u32 (b : ByteArray) (n : Nat) : ByteArray := word b (UInt32.ofNat n)

@[inline] def i32 (b : ByteArray) (v : Int) : ByteArray := word b (i32Word v)

@[inline] def bool (b : ByteArray) (v : Bool) : ByteArray := b.push (if v then 1 else 0)

@[inline] def str (b : ByteArray) (s : String) : ByteArray := u32 b s.toUTF8.size ++ s.toUTF8

@[inline] def u64 (b : ByteArray) (n : Nat) : ByteArray :=
  u32 (u32 b (n % 4294967296)) (n / 4294967296)

@[inline] def i64 (b : ByteArray) (v : Int) : ByteArray := u64 b (toU64 v)

@[inline] def bytes (b : ByteArray) (x : ByteArray) : ByteArray := u32 b x.size ++ x

@[inline] def pad (b : ByteArray) : Nat → ByteArray
  | 0 => b
  | n + 1 => pad (b.push 0) n

/-- Overwrite the four bytes at `i` with `n` (for a section length, once the body is known). -/
@[inline] def setU32 (b : ByteArray) (i n : Nat) : ByteArray :=
  (((b.set! i (UInt8.ofNat n)).set! (i + 1) (UInt8.ofNat (n / 256))).set! (i + 2)
    (UInt8.ofNat (n / 65536))).set! (i + 3) (UInt8.ofNat (n / 16777216))

@[simp] theorem u8_data (b : ByteArray) (v : UInt8) :
    (u8 b v).data.toList = b.data.toList ++ [v] := by
  simp only [u8, ByteArray.data_push, Array.toList_push]

theorem shift8 (n : Nat) : ((UInt32.ofNat n) >>> 8).toUInt8 = UInt8.ofNat (n / 256) := by
  apply UInt8.toNat_inj.mp
  simp only [UInt32.toNat_toUInt8, UInt32.toNat_shiftRight, UInt32.toNat_ofNat', Nat.reducePow,
      UInt32.reduceToNat, Nat.reduceMod, UInt8.toNat_ofNat']
  omega

theorem shift16 (n : Nat) : ((UInt32.ofNat n) >>> 16).toUInt8 = UInt8.ofNat (n / 65536) := by
  apply UInt8.toNat_inj.mp
  simp only [UInt32.toNat_toUInt8, UInt32.toNat_shiftRight, UInt32.toNat_ofNat', Nat.reducePow,
      UInt32.reduceToNat, Nat.reduceMod, UInt8.toNat_ofNat']
  omega

theorem shift24 (n : Nat) : ((UInt32.ofNat n) >>> 24).toUInt8 = UInt8.ofNat (n / 16777216) := by
  apply UInt8.toNat_inj.mp
  simp only [UInt32.toNat_toUInt8, UInt32.toNat_shiftRight, UInt32.toNat_ofNat', Nat.reducePow,
      UInt32.reduceToNat, Nat.reduceMod, UInt8.toNat_ofNat']
  omega

@[simp] theorem u32_data (b : ByteArray) (n : Nat) :
    (u32 b n).data.toList = b.data.toList ++ Enc.u32 n := by
  have h0 : (UInt32.ofNat n).toUInt8 = UInt8.ofNat n := by
    apply UInt8.toNat_inj.mp; simp only [UInt32.toUInt8_ofNat', UInt8.toNat_ofNat', Nat.reducePow]
  simp only [u32, word, h0, shift8, shift16, shift24, ByteArray.data_push, Array.toList_push,
      List.append_assoc, List.cons_append, List.nil_append, Enc.u32]

@[simp] theorem i32_data (b : ByteArray) (v : Int) :
    (i32 b v).data.toList = b.data.toList ++ Enc.i32 v := by
  rw [i32, i32Word_eq, ← u32, u32_data, Enc.i32]

@[simp] theorem bool_data (b : ByteArray) (v : Bool) :
    (bool b v).data.toList = b.data.toList ++ Enc.bool v := by
  simp only [bool, ByteArray.data_push, Array.toList_push, Enc.bool]

@[simp] theorem str_data (b : ByteArray) (s : String) :
    (str b s).data.toList = b.data.toList ++ Enc.str s := by
  simp only [str, String.toUTF8_eq_toByteArray, String.size_toByteArray, ByteArray.data_append,
      Array.toList_append, u32_data, List.append_assoc, Enc.str]

@[simp] theorem u64_data (b : ByteArray) (n : Nat) :
    (u64 b n).data.toList = b.data.toList ++ Enc.u64 n := by
  simp only [u64, u32_data, List.append_assoc, Enc.u64]

@[simp] theorem i64_data (b : ByteArray) (v : Int) :
    (i64 b v).data.toList = b.data.toList ++ Enc.i64 v := by
  simp only [i64, u64_data, Enc.i64]

@[simp] theorem bytes_data (b x : ByteArray) :
    (bytes b x).data.toList = b.data.toList ++ Enc.bytes x := by
  simp only [bytes, ByteArray.data_append, Array.toList_append, u32_data, List.append_assoc,
      Enc.bytes]

@[simp] theorem pad_data (b : ByteArray) (n : Nat) :
    (pad b n).data.toList = b.data.toList ++ Enc.pad n := by
  induction n generalizing b with
  | zero => simp only [pad, Enc.pad, List.replicate_zero, List.append_nil]
  | succ n ih => simp only [pad, ih, ByteArray.data_push, Array.toList_push, Enc.pad,
      List.append_assoc, List.cons_append, List.nil_append, List.replicate_succ]

end Put

end Cairn.Wire
