module

public import Cairn.Input
public import Cairn.Frame.Encode

/-! Event byte format v1 (host → Lean, docs/frame.md): specification encoder
`Wire.Enc.events`, decoder `Wire.Dec.events`, and the round trip `decodeEvents_encodeEvents`.

```
header  "CAEV" u16 version=1 u16 flags=0 u32 count                          12 bytes
events  count records, each [tag, a, b, 0] then fixed fields, then at most one string
```

Lean only decodes events at run time (the host encodes them), and a frame's events are a
handful of records, so the decoder runs the list specification directly on the buffer's bytes. -/

@[expose] public section

namespace Cairn.Wire

def Button.code : Button → UInt8
  | .primary => 0 | .secondary => 1

def Button.ofCode : UInt8 → Option Button
  | 0 => some .primary | 1 => some .secondary | _ => none

@[simp] theorem Button.ofCode_code (b : Button) : Button.ofCode (Button.code b) = some b := by
  cases b <;> rfl

/-- `char` is 13 and carries its scalar in the record's `u32` field. -/
def Key.code : Key → UInt8
  | .enter => 0 | .escape => 1 | .tab => 2 | .backspace => 3 | .delete => 4
  | .left => 5 | .right => 6 | .up => 7 | .down => 8 | .home => 9 | .finish => 10
  | .pageUp => 11 | .pageDown => 12 | .char _ => 13

def Key.scalar : Key → Nat
  | .char c => c.toNat
  | _ => 0

def Key.ofCode (code : UInt8) (scalar : Nat) : Option Key :=
  match code with
  | 0 => some .enter | 1 => some .escape | 2 => some .tab | 3 => some .backspace
  | 4 => some .delete | 5 => some .left | 6 => some .right | 7 => some .up | 8 => some .down
  | 9 => some .home | 10 => some .finish | 11 => some .pageUp | 12 => some .pageDown
  | 13 => if scalar.isValidChar then some (.char (Char.ofNat scalar)) else none
  | _ => none

@[simp] theorem Key.ofCode_code (k : Key) : Key.ofCode (Key.code k) (Key.scalar k) = some k := by
  cases k with
  | char c =>
    have : c.toNat.isValidChar := c.valid
    simp only [ofCode, code, scalar, this, ↓reduceIte, Char.ofNat_toNat]
  | _ => rfl

theorem Key.scalar_fits (k : Key) : FitsU32 (Key.scalar k) := by
  cases k with
  | char c =>
    have h : c.toNat.isValidChar := c.valid
    simp only [scalar, FitsU32]; unfold Nat.isValidChar at h; omega
  | _ => decide

/-- Bit 0 shift, 1 command, 2 option, 3 control. -/
def Mods.code (m : Mods) : UInt8 :=
  UInt8.ofNat ((if m.shift then 1 else 0) + (if m.command then 2 else 0) +
    (if m.option then 4 else 0) + (if m.control then 8 else 0))

def Mods.ofCode (b : UInt8) : Option Mods :=
  let n := b.toNat
  if n < 16 then
    some ⟨n % 2 == 1, n / 2 % 2 == 1, n / 4 % 2 == 1, n / 8 % 2 == 1⟩
  else none

@[simp] theorem Mods.ofCode_code (m : Mods) : Mods.ofCode (Mods.code m) = some m := by
  obtain ⟨s, c, o, t⟩ := m
  cases s <;> cases c <;> cases o <;> cases t <;> rfl

def fitsEvent : Event → Bool
  | .pointerMove p => fi p.x && fi p.y
  | .pointerDown p _ clicks _ => fi p.x && fi p.y && fu clicks
  | .pointerUp p _ _ => fi p.x && fi p.y
  | .scroll p dx dy => fi p.x && fi p.y && fi dx && fi dy
  | .insertText s rep => fs s && rep.all fitsRange
  | .setMarked s a l rep => fs s && fu a && fu l && rep.all fitsRange
  | .paste s => fs s
  | .resize sz => fi sz.w && fi sz.h
  | .scale p => fu p
  | _ => true

namespace Enc

/-- The record head: tag, two small fields, a reserved zero. -/
def head (tag a b : UInt8) : List UInt8 := [tag, a, b, 0]

def event : Event → List UInt8
  | .pointerMove p => head 0 0 0 ++ point p
  | .pointerDown p b clicks m => head 1 (Button.code b) (Mods.code m) ++ point p ++ u32 clicks
  | .pointerUp p b m => head 2 (Button.code b) (Mods.code m) ++ point p
  | .pointerExit => head 3 0 0
  | .scroll p dx dy => head 4 0 0 ++ point p ++ i32 dx ++ i32 dy
  | .key k m => head 5 (Key.code k) (Mods.code m) ++ u32 (Key.scalar k)
  | .insertText s rep =>
    head 6 (if rep.isSome then 1 else 0) 0 ++ range (rep.getD (0, 0)) ++ str s
  | .setMarked s a l rep =>
    head 7 (if rep.isSome then 1 else 0) 0 ++ range (rep.getD (0, 0)) ++ u32 a ++ u32 l ++ str s
  | .unmark => head 8 0 0
  | .copy => head 9 0 0
  | .cut => head 10 0 0
  | .selectAll => head 11 0 0
  | .undo => head 12 0 0
  | .redo => head 13 0 0
  | .paste s => head 14 0 0 ++ str s
  | .resize sz => head 15 0 0 ++ size sz
  | .scale p => head 16 0 0 ++ u32 p
  | .windowFocus b => head 17 (if b then 1 else 0) 0

def eventsMagic : List UInt8 := [0x43, 0x41, 0x45, 0x56] -- "CAEV"

def eventsHeader : List UInt8 := eventsMagic ++ [1, 0, 0, 0]

def events (es : List Event) : List UInt8 :=
  eventsHeader ++ u32 es.length ++ es.flatMap event

end Enc

namespace Dec

def opt {α : Type} (present : UInt8) (a : α) : Dec (Option α) :=
  match present with
  | 0 => pure none
  | 1 => pure (some a)
  | _ => fail

def event : Dec Event := do
  let tag ← byte
  let a ← byte
  let b ← byte
  skip 1
  match tag with
  | 0 => return .pointerMove (← point)
  | 1 =>
    let some btn := Button.ofCode a | fail
    let some m := Mods.ofCode b | fail
    let p ← point
    let clicks ← u32
    return .pointerDown p btn clicks m
  | 2 =>
    let some btn := Button.ofCode a | fail
    let some m := Mods.ofCode b | fail
    return .pointerUp (← point) btn m
  | 3 => return .pointerExit
  | 4 =>
    let p ← point
    let dx ← i32
    let dy ← i32
    return .scroll p dx dy
  | 5 =>
    let some m := Mods.ofCode b | fail
    let scalar ← u32
    let some k := Key.ofCode a scalar | fail
    return .key k m
  | 6 =>
    let r ← range
    let rep ← opt a r
    return .insertText (← str) rep
  | 7 =>
    let r ← range
    let rep ← opt a r
    let selStart ← u32
    let selLen ← u32
    return .setMarked (← str) selStart selLen rep
  | 8 => return .unmark
  | 9 => return .copy
  | 10 => return .cut
  | 11 => return .selectAll
  | 12 => return .undo
  | 13 => return .redo
  | 14 => return .paste (← str)
  | 15 => return .resize (← size)
  | 16 => return .scale (← u32)
  | 17 =>
    match a with
    | 0 => return .windowFocus false
    | 1 => return .windowFocus true
    | _ => fail
  | _ => fail

def events : Dec (List Event) := do
  expect Enc.eventsHeader
  let n ← u32
  count event n

theorem opt_isSome {α : Type} (o : Option α) (d : α) (r : List UInt8) :
    opt (if o.isSome then 1 else 0) (o.getD d) r = some (o, r) := by
  cases o <;> rfl

theorem event_enc {e : Event} (h : fitsEvent e = true) (r : List UInt8) :
    event (Enc.event e ++ r) = some (e, r) := by
  have hz : ∀ r', skip 1 ((0 : UInt8) :: r') = some ((), r') := fun r' => skip_pad 1 r'
  cases e with
  | pointerMove p =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, h, point_enc, pure_apply]
  | pointerDown p btn clicks m =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff, fu_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, Button.ofCode_code, Mods.ofCode_code, hz, h, point_enc, u32_enc,
        pure_apply]
  | pointerUp p btn m =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        Button.ofCode_code, Mods.ofCode_code, hz, h, point_enc, pure_apply]
  | scroll p dx dy =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, h, point_enc, i32_enc, pure_apply]
  | key k m =>
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        Mods.ofCode_code, hz, (Key.scalar_fits k), u32_enc, Key.ofCode_code, pure_apply]
  | insertText s rep =>
    simp only [fitsEvent, Bool.and_eq_true, fs_iff] at h
    obtain ⟨hs, hr⟩ := h
    have hr' : fitsRange (rep.getD (0,
        0)) = true := by cases rep <;> simp_all only [Option.all_none, Option.getD_none,
        fitsRange_zero, Option.all_some, Option.getD_some]
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, range_enc hr', opt_isSome, str_enc hs, pure_apply]
  | setMarked s a l rep =>
    simp only [fitsEvent, Bool.and_eq_true, fs_iff, fu_iff] at h
    obtain ⟨⟨⟨hs, ha⟩, hl⟩, hr⟩ := h
    have hr' : fitsRange (rep.getD (0,
        0)) = true := by cases rep <;> simp_all only [Option.all_none, Option.getD_none,
        fitsRange_zero, Option.all_some, Option.getD_some]
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, range_enc hr', opt_isSome, ha, u32_enc, hl, str_enc hs,
        pure_apply]
  | paste s =>
    simp only [fitsEvent, fs_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, str_enc h, pure_apply]
  | resize sz =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, size_enc h.1 h.2, pure_apply]
  | scale p =>
    simp only [fitsEvent, fu_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, u32_enc h, pure_apply]
  | windowFocus b => cases b <;> rfl
  | pointerExit | unmark | copy | cut | selectAll | undo | redo => rfl

theorem events_enc {es : List Event} (h : ∀ e ∈ es, fitsEvent e = true)
    (hn : FitsU32 es.length) (r : List UInt8) :
    events (Enc.events es ++ r) = some (es, r) := by
  simp only [events, Enc.events, List.append_assoc, bind_apply, expect_enc, u32_enc hn]
  exact count_enc es (fun e he => event_enc (h e he)) r

end Dec

end Cairn.Wire

namespace Cairn

open Wire

def encodeEvents (es : Array Event) : ByteArray := ⟨(Enc.events es.toList).toArray⟩

def decodeEvents (b : ByteArray) : Option (Array Event) :=
  (Dec.run Dec.events b.data.toList).map List.toArray

/-- **Round trip.** Every batch of events whose values fit the wire's fields decodes to itself. -/
theorem decodeEvents_encodeEvents (es : Array Event) (h : es.all fitsEvent = true)
    (hn : es.size < 4294967296) : decodeEvents (encodeEvents es) = some es := by
  simp only [Array.all_eq_true'] at h
  have := Dec.events_enc (es := es.toList) (fun e he => h e (by simpa using he))
    (by simpa [FitsU32] using hn) []
  simp only [decodeEvents, encodeEvents, Dec.run_enc this, Option.map_some, Array.toArray_toList]

end Cairn

