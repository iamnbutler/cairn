module

public import Cairn.Input
public import Cairn.Frame.Encode

/-! Event byte format v2 (host → Lean, docs/frame.md): specification encoder
`Wire.Enc.events`, decoder `Wire.Dec.events`, and the round trip `decodeEvents_encodeEvents`.

```
header  "CAEV" u16 version=2 u16 flags=0 u32 count                          12 bytes
events  count records, each [tag, a, b, 0] then fixed fields, then at most one string
```

A `surface` record (tag 21) is its head and a `u32` place followed by one whole surface-local
record (tags 0–17), so every record still stands alone.

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

def Fault.code : Fault → UInt8
  | .notFound => 0 | .denied => 1 | .timeout => 2 | .network => 3 | .invalid => 4 | .other => 5

def Fault.ofCode : UInt8 → Option Fault
  | 0 => some .notFound | 1 => some .denied | 2 => some .timeout | 3 => some .network
  | 4 => some .invalid | 5 => some .other | _ => none

@[simp] theorem Fault.ofCode_code (f : Fault) : Fault.ofCode (Fault.code f) = some f := by
  cases f <;> rfl

/-- `done` 0, `bytes` 1, `http` 2, `failed` 3, `names` 4, `app` 5, `flag` 6, `image` 7. -/
def Reply.code : Reply → UInt8
  | .done => 0 | .bytes _ => 1 | .http .. => 2 | .failed .. => 3
  | .names _ => 4 | .app .. => 5 | .flag _ => 6 | .image .. => 7

def Reply.faultCode : Reply → UInt8
  | .failed f _ => Fault.code f
  | _ => 0

/-- `tick` 0, `changed` 1, `audio` 2, `keyDown` 3, `keyUp` 4, `otherKey` 5, `failed` 6,
`started` 7. -/
def SubEvent.code : SubEvent → UInt8
  | .tick => 0 | .changed => 1 | .audio .. => 2 | .keyDown _ => 3 | .keyUp _ => 4
  | .otherKey _ => 5 | .failed .. => 6 | .started _ => 7

def SubEvent.faultCode : SubEvent → UInt8
  | .failed f _ => Fault.code f
  | _ => 0

def fitsTime (t : Time) : Bool := fu64 t.mono && fi64 t.wall && fi t.zone

def fitsLevel (l : Level) : Bool := fu64 l.sumSq && fu l.peak

def fitsSubEvent : SubEvent → Bool
  | .tick | .changed => true
  | .audio n pk ws => fu n && fu pk && fu ws.length && ws.all fitsLevel
  | .keyDown t | .keyUp t | .otherKey t | .started t => fu64 t
  | .failed _ m => fs m

def fitsReply : Reply → Bool
  | .done => true
  | .bytes d => fb d
  | .http st hs b => fu st && fitsHeaders hs && fb b
  | .failed _ m => fs m
  | .names ns => fu ns.length && ns.all fs
  | .app pid n => fu pid && fs n
  | .flag _ => true
  | .image w h => fu w && fu h

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
  | .subEvent id e => fu id && fitsSubEvent e
  | .surface p e => fu p && e.isLocal && fitsEvent e
  | .menuOpen p | .menuClose p => fu p
  | .menuSelect p r => fu p && fitsRef r
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
  | .image w h => u32 w ++ u32 h

def level (l : Level) : List UInt8 := u64 l.sumSq ++ u32 l.peak

/-- A subscription event's fields after its record head and id. -/
def subEventBody : SubEvent → List UInt8
  | .tick | .changed => []
  | .audio n pk ws => u32 n ++ u32 pk ++ u32 ws.length ++ ws.flatMap level
  | .keyDown t | .keyUp t | .otherKey t | .started t => u64 t
  | .failed _ m => str m

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
  | .subEvent id e => head 20 (SubEvent.code e) (SubEvent.faultCode e) ++ u32 id ++ subEventBody e
  | .surface p e => head 21 0 0 ++ u32 p ++ event e
  | .menuOpen p => head 22 0 0 ++ u32 p
  | .menuClose p => head 23 0 0 ++ u32 p
  | .menuSelect p r => head 24 0 0 ++ u32 p ++ ref r

def eventsMagic : List UInt8 := [0x43, 0x41, 0x45, 0x56] -- "CAEV"

def eventsHeader : List UInt8 := eventsMagic ++ [2, 0, 0, 0]

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
  | 7 => if fault = 0 then do
      let w ← u32
      return .image w (← u32)
    else fail
  | _ => fail

def level : Dec Level := do
  let s ← u64
  return ⟨s, ← u32⟩

/-- The body of a subscription event with code `code`; only `failed` has a fault. -/
def subEventBody (code fault : UInt8) : Dec SubEvent :=
  match code with
  | 0 => if fault = 0 then pure .tick else fail
  | 1 => if fault = 0 then pure .changed else fail
  | 2 => if fault = 0 then do
      let n ← u32
      let pk ← u32
      let c ← u32
      return .audio n pk (← count level c)
    else fail
  | 3 => if fault = 0 then do return .keyDown (← u64) else fail
  | 4 => if fault = 0 then do return .keyUp (← u64) else fail
  | 5 => if fault = 0 then do return .otherKey (← u64) else fail
  | 6 => do
    let some f := Fault.ofCode fault | fail
    return .failed f (← str)
  | 7 => if fault = 0 then do return .started (← u64) else fail
  | _ => fail

/-- Read a record head, then the rest of the record by its tag. -/
def headed (k : UInt8 → UInt8 → UInt8 → Dec Event) : Dec Event := do
  let tag ← byte
  let a ← byte
  let b ← byte
  skip 1
  k tag a b

/-- Every record but `surface`, after its head. -/
def body (tag a b : UInt8) : Dec Event := do
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
    let id ← u32
    return .subEvent id (← subEventBody a b)
  | 22 => return .menuOpen (← u32)
  | 23 => return .menuClose (← u32)
  | 24 =>
    let p ← u32
    return .menuSelect p (← ref)
  | _ => fail

/-- A record other than `surface`. -/
def plain : Dec Event := headed body

/-- One record. A `surface` record holds exactly one surface-local record. -/
def event : Dec Event := headed fun tag a b =>
  if tag = 21 then
    if a = 0 ∧ b = 0 then do
      let p ← u32
      let e ← plain
      if e.isLocal then pure (.surface p e) else fail
    else fail
  else body tag a b

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
  | image w h =>
    simp only [fitsReply, Bool.and_eq_true, fu_iff] at h
    simp only [replyBody, Reply.code, Reply.faultCode, Enc.replyBody, ↓reduceIte,
        List.append_assoc, bind_apply, u32_enc h.1, u32_enc h.2, pure_apply]

theorem level_enc {l : Level} (h : fitsLevel l = true) (r : List UInt8) :
    level (Enc.level l ++ r) = some (l, r) := by
  simp only [fitsLevel, Bool.and_eq_true, fu64_iff, fu_iff] at h
  simp only [level, Enc.level, List.append_assoc, bind_apply, u64_enc h.1, u32_enc h.2, pure_apply]

theorem subEventBody_enc {e : SubEvent} (h : fitsSubEvent e = true) (r : List UInt8) :
    subEventBody (SubEvent.code e) (SubEvent.faultCode e) (Enc.subEventBody e ++ r) =
      some (e, r) := by
  cases e with
  | tick | changed => rfl
  | audio n pk ws =>
    simp only [fitsSubEvent, Bool.and_eq_true, fu_iff, List.all_eq_true] at h
    obtain ⟨⟨⟨hn, hp⟩, hc⟩, hw⟩ := h
    simp only [subEventBody, SubEvent.code, SubEvent.faultCode, Enc.subEventBody, ↓reduceIte,
        List.append_assoc, bind_apply, u32_enc hn, u32_enc hp, u32_enc hc]
    rw [count_enc ws (fun l hl => level_enc (hw l hl)) r]; rfl
  | keyDown t | keyUp t | otherKey t | started t =>
    simp only [fitsSubEvent, fu64_iff] at h
    simp only [subEventBody, SubEvent.code, SubEvent.faultCode, Enc.subEventBody, ↓reduceIte,
        bind_apply, u64_enc h, pure_apply]
  | failed f m =>
    simp only [fitsSubEvent, fs_iff] at h
    simp only [subEventBody, SubEvent.code, SubEvent.faultCode, Enc.subEventBody,
        Fault.ofCode_code, bind_apply, str_enc h, pure_apply]

theorem plain_enc {e : Event} (h : fitsEvent e = true) (hs : e.isSurface = false) (r : List UInt8) :
    plain (Enc.event e ++ r) = some (e, r) := by
  have hz : ∀ r', skip 1 ((0 : UInt8) :: r') = some ((), r') := fun r' => skip_pad 1 r'
  cases e with
  | pointerMove p =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, h, point_enc, pure_apply]
  | pointerDown p btn clicks m =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff, fu_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, Button.ofCode_code, Mods.ofCode_code, hz, h, point_enc, u32_enc,
        pure_apply]
  | pointerUp p btn m =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        Button.ofCode_code, Mods.ofCode_code, hz, h, point_enc, pure_apply]
  | scroll p dx dy =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, h, point_enc, i32_enc, pure_apply]
  | key k m =>
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        Mods.ofCode_code, hz, (Key.scalar_fits k), u32_enc, Key.ofCode_code, pure_apply]
  | insertText s rep =>
    simp only [fitsEvent, Bool.and_eq_true, fs_iff] at h
    obtain ⟨hs, hr⟩ := h
    have hr' : fitsRange (rep.getD (0,
        0)) = true := by cases rep <;> simp_all only [Option.all_none, Option.getD_none,
        fitsRange_zero, Option.all_some, Option.getD_some]
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, range_enc hr', opt_isSome, str_enc hs, pure_apply]
  | setMarked s a l rep =>
    simp only [fitsEvent, Bool.and_eq_true, fs_iff, fu_iff] at h
    obtain ⟨⟨⟨hs, ha⟩, hl⟩, hr⟩ := h
    have hr' : fitsRange (rep.getD (0,
        0)) = true := by cases rep <;> simp_all only [Option.all_none, Option.getD_none,
        fitsRange_zero, Option.all_some, Option.getD_some]
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, range_enc hr', opt_isSome, ha, u32_enc, hl, str_enc hs,
        pure_apply]
  | paste s =>
    simp only [fitsEvent, fs_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, str_enc h, pure_apply]
  | resize sz =>
    simp only [fitsEvent, Bool.and_eq_true, fi_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, size_enc h.1 h.2, pure_apply]
  | scale p =>
    simp only [fitsEvent, fu_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, bind_apply, byte_cons,
        hz, u32_enc h, pure_apply]
  | windowFocus b => cases b <;> rfl
  | surface _ _ => simp only [Event.isSurface, Bool.true_eq_false] at hs
  | clock t =>
    simp only [fitsEvent, fitsTime, Bool.and_eq_true, fu64_iff, fi64_iff, fi_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, u64_enc h.1.1, i64_enc h.1.2, i32_enc h.2, pure_apply]
  | reply id rp =>
    simp only [fitsEvent, Bool.and_eq_true, fu_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, u32_enc h.1]
    rw [replyBody_enc h.2]; rfl
  | subEvent id e =>
    simp only [fitsEvent, Bool.and_eq_true, fu_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, hz, u32_enc h.1]
    rw [subEventBody_enc h.2]; rfl
  | menuOpen p | menuClose p =>
    simp only [fitsEvent, fu_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append,
        bind_apply, byte_cons, hz, u32_enc h, pure_apply]
  | menuSelect p c =>
    simp only [fitsEvent, Bool.and_eq_true, fu_iff] at h
    simp only [plain, headed, body, Enc.event, Enc.head, List.cons_append, List.nil_append,
        List.append_assoc, bind_apply, byte_cons, hz, u32_enc h.1, ref_enc h.2, pure_apply]
  | pointerExit | unmark | copy | cut | selectAll | undo | redo => rfl

/-- On a record whose tag isn't `surface`'s, `event` is `plain`. -/
theorem event_eq_plain (t : UInt8) (l : List UInt8) (ht : t ≠ 21) :
    event (t :: l) = plain (t :: l) := by
  simp only [event, plain, headed, bind_apply, byte_cons, ht, ite_false]

theorem event_enc {e : Event} (h : fitsEvent e = true) (r : List UInt8) :
    event (Enc.event e ++ r) = some (e, r) := by
  have hz : ∀ r', skip 1 ((0 : UInt8) :: r') = some ((), r') := fun r' => skip_pad 1 r'
  cases hs : e.isSurface with
  | false =>
    have : ∃ t l, Enc.event e ++ r = t :: l ∧ t ≠ 21 := by
      cases e <;> first
        | exact ⟨_, _, rfl, by decide⟩
        | simp only [Event.isSurface, Bool.true_eq_false] at hs
    obtain ⟨t, l, he, ht⟩ := this
    rw [he, event_eq_plain t l ht, ← he]
    exact plain_enc h hs r
  | true =>
    cases e with
    | surface p e =>
      simp only [fitsEvent, Bool.and_eq_true, fu_iff] at h
      obtain ⟨⟨hp, hl⟩, he⟩ := h
      have hs' : e.isSurface = false := by
        cases e <;> simp_all only [Event.isLocal, Event.isSurface, Bool.false_eq_true]
      simp only [event, headed, Enc.event, Enc.head, List.cons_append, List.nil_append,
          List.append_assoc, bind_apply, byte_cons, hz, ite_true, and_self, u32_enc hp,
          plain_enc he hs', hl, pure_apply]
    | _ => simp only [Event.isSurface, Bool.false_eq_true] at hs

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

