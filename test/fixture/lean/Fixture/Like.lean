module

public import Cairn

/-! # Likes: toggles a server keeps

The fixture's Like buttons (`^21#k`, posts 1 to 4): each is a toggle whose value a server holds,
written the way an optimistic table writes it (docs/goals/m5.md, "How an act works"):

- a press flips what is shown (`want`) at once and, if nothing is in flight for the post, sends
  a write of it (`PUT`, idempotent: it sets the value);
- an acknowledged write (2xx) makes the written value the server's (`known`), and one more is
  sent if a press changed `want` meanwhile;
- a refused write (4xx) rolls `want` back to `known`;
- a lost write (a timeout, a network failure, a 5xx) may or may not have happened: the post
  stays as shown and the value is read back (`GET`); the read settles it, and a failed read is
  retried on a timer.

`cairn fuzz` checks it against a fake server that keeps the values (Fixture/Fuzz.lean,
`Cairn.Fuzz.Server`), with replies failed before and lost after the server acted. `receive`'s
`blind` is the mutant Fixture/LikeMutant.lean catches: after a lost write it sends the write
again instead of reading. A refusal of that retry then rolls back to a value the server no
longer holds.

Requests go to `127.0.0.1:9`, where nothing listens, so in the real app every write is lost and
read back every two seconds; the server is the fuzzer's. -/

@[expose] public section

namespace Fixture.Like
open Cairn

/-- How many posts have a Like button, keyed 1 to `posts`. -/
def posts : Nat := 4

/-- What a post's like waits on. -/
inductive Wait where
  | idle
  /-- A write of `v`, request `req`, is in flight. -/
  | write (req : Nat) (v : Bool)
  /-- After a lost write, a read back, request `req`, is in flight. -/
  | read (req : Nat)
  /-- A read back failed; its timer sends another. -/
  | backoff
deriving Repr, DecidableEq, Inhabited

structure Entry where
  /-- What is shown. -/
  want : Bool := false
  /-- The server's value, as last heard. -/
  known : Bool := false
  wait : Wait := .idle
deriving Repr, DecidableEq, Inhabited

/-- With nothing in flight or in doubt, a post shows the value last heard from the server. -/
def Entry.ok (e : Entry) : Prop := e.wait = .idle → e.want = e.known

instance : DecidablePred Entry.ok := fun e => by unfold Entry.ok; infer_instance

/-- The posts' likes at first: none liked, nothing in flight. -/
def init : List Entry := List.replicate posts {}

def url (k : Nat) : String := s!"http://127.0.0.1:9/like/{k}"
def bit (v : Bool) : ByteArray := (if v then "1" else "0").toUTF8
def writeReq (k : Nat) (v : Bool) : Request := .http "PUT" (url k) [] (bit v) 5000
def readReq (k : Nat) : Request := .http "GET" (url k) [] .empty 5000
def timerName (k : Nat) : String := s!"like-{k}"
def retryMs : Nat := 2000

/-- An entry, the next request id and the effects to send. -/
abbrev Out := Entry × Nat × List Effect

/-- If nothing is in flight and what is shown isn't the server's value, write it. -/
def settle (k : Nat) (e : Entry) (n : Nat) : Out :=
  if e.wait = .idle ∧ e.want ≠ e.known then
    ({ e with wait := .write n e.want }, n + 1, [.request n (writeReq k e.want)])
  else (e, n, [])

theorem settle_ok (k : Nat) (e : Entry) (n : Nat) : (settle k e n).1.ok := by
  unfold settle
  split
  · intro h; cases h
  · rename_i h; intro hi; exact Classical.byContradiction fun hne => h ⟨hi, hne⟩

/-- A press of post `k`'s Like. -/
def press (k : Nat) (e : Entry) (n : Nat) : Out := settle k { e with want := !e.want } n

/-- The answer to the request `e` waits on. `blind`: the mutant, which writes again after a lost
write instead of reading. -/
def answer (blind : Bool) (k : Nat) (e : Entry) (r : Reply) (n : Nat) : Out :=
  match e.wait, r with
  | .write _ v, .http st _ _ =>
    if 200 ≤ st ∧ st < 300 then settle k { e with known := v, wait := .idle } n
    else if 400 ≤ st ∧ st < 500 then ({ e with want := e.known, wait := .idle }, n, [])
    else lost v
  | .write _ v, _ => lost v
  | .read _, .http st _ b =>
    if st = 200 ∧ (b == bit true || b == bit false) then
      settle k { e with known := b == bit true, wait := .idle } n
    else ({ e with wait := .backoff }, n, [.setTimer (timerName k) retryMs])
  | .read _, _ => ({ e with wait := .backoff }, n, [.setTimer (timerName k) retryMs])
  | _, _ => (e, n, [])
where
  lost (v : Bool) : Out :=
    if blind then ({ e with wait := .write n v }, n + 1, [.request n (writeReq k v)])
    else ({ e with wait := .read n }, n + 1, [.request n (readReq k)])

/-- The read-back timer of a post whose read failed. -/
def retry (k : Nat) (e : Entry) (n : Nat) : Out :=
  if e.wait = .backoff then ({ e with wait := .read n }, n + 1, [.request n (readReq k)])
  else (e, n, [])

theorem press_ok (k : Nat) (e : Entry) (n : Nat) : (press k e n).1.ok := settle_ok k _ n

theorem answer_ok (blind : Bool) (k : Nat) (e : Entry) (r : Reply) (n : Nat) (h : e.ok) :
    (answer blind k e r n).1.ok := by
  have hl : ∀ v, (answer.lost blind k e n v).1.ok := by
    intro v; unfold answer.lost; split <;> (intro hw; cases hw)
  unfold answer
  split
  · split
    · exact settle_ok k _ n
    · split
      · intro _; rfl
      · exact hl _
  · exact hl _
  · split
    · exact settle_ok k _ n
    · intro hw; cases hw
  · intro hw; cases hw
  · exact h

theorem retry_ok (k : Nat) (e : Entry) (n : Nat) (h : e.ok) : (retry k e n).1.ok := by
  unfold retry; split
  · intro hw; cases hw
  · exact h

/-! ## The table -/

/-- Post `k`'s entry changed by `f`: the table, the next request id and the effects. A key
that isn't a post changes nothing. -/
def at_ (t : List Entry) (k : Nat) (f : Entry → Nat → Out) (n : Nat) :
    List Entry × Nat × List Effect :=
  match t[k - 1]? with
  | some e => let o := f e n; (t.set (k - 1) o.1, o.2.1, o.2.2)
  | none => (t, n, [])

/-- Every post is `ok`. -/
def AllOk (t : List Entry) : Prop := ∀ e ∈ t, e.ok

theorem at_ok {t : List Entry} {k : Nat} {f : Entry → Nat → Out} {n : Nat} (ht : AllOk t)
    (hf : ∀ e n, e.ok → (f e n).1.ok) : AllOk (at_ t k f n).1 := by
  unfold at_
  split
  · rename_i e he
    intro x hx
    rcases List.mem_or_eq_of_mem_set hx with hx | rfl
    · exact ht x hx
    · exact hf e n (ht e (List.mem_of_getElem? he))
  · exact ht

/-- The post waiting on request `id`, if any (keys from 1). -/
def waiting (t : List Entry) (id : Nat) : Option Nat :=
  (t.findIdx? fun e => match e.wait with
    | .write r _ | .read r => r == id
    | _ => false).map (· + 1)

/-- A message from the world: a reply to a post's request, or a post's read-back timer. -/
def receive (blind : Bool := false) (t : List Entry) (n : Nat) : Msg → List Entry × Nat × List Effect
  | .reply id r =>
    match waiting t id with
    | some k => at_ t k (fun e n => answer blind k e r n) n
    | none => (t, n, [])
  | .timer name =>
    match (List.range' 1 posts).find? (timerName · == name) with
    | some k => at_ t k (retry k) n
    | none => (t, n, [])
  | _ => (t, n, [])

theorem receive_ok (blind : Bool) {t : List Entry} (n : Nat) (m : Msg) (h : AllOk t) :
    AllOk (receive blind t n m).1 := by
  unfold receive
  split
  · split
    · exact at_ok h fun e n he => answer_ok blind _ e _ n he
    · exact h
  · split
    · exact at_ok h fun e n he => retry_ok _ e n he
    · exact h
  · exact h

theorem press_all_ok {t : List Entry} (k n : Nat) (h : AllOk t) :
    AllOk (at_ t k (press k) n).1 :=
  at_ok h fun e n _ => press_ok k e n

end Fixture.Like
