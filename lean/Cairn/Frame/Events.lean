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

def Fault.code : Fault → UInt8
  | .notFound => 0 | .denied => 1 | .timeout => 2 | .network => 3 | .invalid => 4 | .other => 5

def Fault.ofCode : UInt8 → Option Fault
  | 0 => some .notFound | 1 => some .denied | 2 => some .timeout | 3 => some .network
  | 4 => some .invalid | 5 => some .other | _ => none

@[simp] theorem Fault.ofCode_code (f : Fault) : Fault.ofCode (Fault.code f) = some f := by
  cases f <;> rfl

/-- `done` 0, `bytes` 1, `http` 2, `failed` 3, `names` 4, `app` 5, `flag` 6. -/
def Reply.code : Reply → UInt8
  | .done => 0 | .bytes _ => 1 | .http .. => 2 | .failed .. => 3
  | .names _ => 4 | .app .. => 5 | .flag _ => 6

def Reply.faultCode : Reply → UInt8
  | .failed f _ => Fault.code f
  | _ => 0

def SubEvent.code : SubEvent → UInt8
  | .tick => 0 | .changed => 1

def SubEvent.ofCode : UInt8 → Option SubEvent
  | 0 => some .tick | 1 => some .changed | _ => none

@[simp] theorem SubEvent.ofCode_code (e : SubEvent) : SubEvent.ofCode (SubEvent.code e) = some e := by
  cases e <;> rfl

def fitsTime (t : Time) : Bool := fu64 t.mono && fi64 t.wall && fi t.zone

def fitsReply : Reply → Bool
  | .done => true
  | .bytes d => fb d
  | .http st hs b => fu st && fitsHeaders hs && fb b
  | .failed _ m => fs m
  | .names ns => fu ns.length && ns.all fs
  | .app pid n => fu pid && fs n
  | .flag _ => true

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
  | .clock t => fitsTime t
  | .reply id r => fu id && fitsReply r
  | .subEvent id _ => fu id
  | _ => true

namespace Enc

/-- The record head: tag, two small fields, a reserved zero. -/
def head (tag a b : UInt8) : List UInt8 := [tag, a, b, 0]

/-- A reply's fields after its record head and id. -/
def replyBody : Reply → List UInt8
  | .done => []
  | .bytes d => bytes d
  | .http st hs b => u32 st ++ headers hs ++ bytes b
  | .failed _ m => str m
  | .names ns => u32 ns.length ++ ns.flatMap str
  | .app pid n => u32 pid ++ str n
  | .flag b => bool b ++ pad 3

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
  | .clock t => head 18 0 0 ++ u64 t.mono ++ i64 t.wall ++ i32 t.zone
  | .reply id r => head 19 (Reply.code r) (Reply.faultCode r) ++ u32 id ++ replyBody r
  | .subEvent id e => head 20 (SubEvent.code e) 0 ++ u32 id

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

def replyBody (code fault : UInt8) : Dec Reply :=
  match code with
  | 0 => if fault = 0 then pure .done else fail
  | 1 => if fault = 0 then do return .bytes (← bytes) else fail
  | 2 => if fault = 0 then do
      let st ← u32
      let hs ← headers
      return .http st hs (← bytes)
    else fail
  | 3 => match Fault.ofCode fault with
    | some f => do return .failed f (← str)
    | none => fail
  | 4 => if fault = 0 then do
      let n ← u32
      return .names (← count str n)
    else fail
  | 5 => if fault = 0 then do
      let pid ← u32
      return .app pid (← str)
    else fail
  | 6 => if fault = 0 then do
      let b ← bool
      skip 3
      return .flag b
    else fail
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
  | 18 =>
    let mono ← u64
    let wall ← i64
    let zone ← i32
    return .clock ⟨mono, wall, zone⟩
  | 19 =>
    let id ← u32
    return .reply id (← replyBody a b)
  | 20 =>
    let some e := SubEvent.ofCode a | fail
    return .subEvent (← u32) e
  | _ => fail

def events : Dec (List Event) := do
  expect Enc.eventsHeader
  let n ← u32
  count event n

theorem opt_isSome {α : Type} (o : Option α) (d : α) (r : List UInt8) :
    opt (if o.isSome then 1 else 0) (o.getD d) r = some (o, r) := by
  cases o <;> rfl

theorem replyBody_enc {rp : Reply} (h : fitsReply rp = true) (r : List UInt8) :
    replyBody (Reply.code rp) (Reply.faultCode rp) (Enc.replyBody rp ++ r) = some (rp, r) := by
  cases rp with
  | done => rfl
  | bytes d =>
    simp only [fitsReply, fb_iff] at h
    simp only [replyBody, Reply.code, Reply.faultCode, Enc.replyBody, ↓reduceIte, bind_apply,
        bytes_enc h, pure_apply]
  | http st hs b =>
    simp only [fitsReply, Bool.and_eq_true, fu_iff, fb_iff] at h
    simp only [replyBody, Reply.code, Reply.faultCode, Enc.replyBody, ↓reduceIte,
        List.append_assoc, bind_apply, u32_enc h.1.1, headers_enc h.1.2, bytes_enc h.2,
        pure_apply]
  | failed f m =>
    simp only [fitsReply, fs_iff] at h
    simp only [replyBody, Reply.code, Reply.faultCode, Enc.replyBody, Fault.ofCode_code,
        bind_apply, str_enc h, pure_apply]
  | names ns =>
    simp only [fitsReply, Bool.and_eq_true, fu_iff, List.all_eq_true, fs_iff] at h
    simp only [replyBody, Reply.code, Reply.faultCode, Enc.replyBody, ↓reduceIte,
        List.append_assoc, bind_apply, u32_enc h.1]
    rw [count_enc ns (fun s hs => str_enc (h.2 s hs)) r]; rfl
  | app pid n =>
    simp only [fitsReply, Bool.and_eq_true, fu_iff, fs_iff] at h
    simp only [replyBody, Reply.code, Reply.faultCode, Enc.replyBody, ↓reduceIte,
        List.append_assoc, bind_apply, u32_enc h.1, str_enc h.2, pure_apply]
  | flag b =>
    simp only [replyBody, Reply.code, Reply.faultCode, Enc.replyBody, ↓reduceIte,
        List.append_assoc, bind_apply, bool_enc, skip_pad, pure_apply]

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
  | clock t =>
    simp only [fitsEvent, fitsTime, Bool.and_eq_true, fu64_iff, fi64_iff, fi_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, u64_enc h.1.1, i64_enc h.1.2, i32_enc h.2, pure_apply]
  | reply id rp =>
    simp only [fitsEvent, Bool.and_eq_true, fu_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, u32_enc h.1]
    rw [replyBody_enc h.2]; rfl
  | subEvent id e =>
    simp only [fitsEvent, fu_iff] at h
    simp only [event, Enc.event, Enc.head, List.cons_append, List.nil_append,
        bind_apply, byte_cons, hz, SubEvent.ofCode_code, u32_enc h, pure_apply]
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

