module

public import Cairn

/-! # Likes: toggles a server keeps

The fixture's Like buttons (`^21#k`, posts 1 to 4), each with its count, on Cairn's optimistic
table (`Cairn.Optimistic`, Cairn's docs/optimistic.md). This is the glue an app writes around a
table, and nothing more:

- a press feeds the table `set k not`: the post shows the new value at once, and the table asks
  for a write if none is in flight for it;
- the table's outputs become requests (`PUT` to set the value, idempotently, and `GET` to read
  it back), timers (the read-back backoff) and the rollback line, and each request id is
  remembered with the ticket it was sent for (`reqs`);
- a reply is classified (2xx `acked`, 4xx `refused`, anything else `lost`; a read's `200` with a
  value `read`, anything else `readFailed`) and fed back under its ticket;
- Refresh (`^23`) fetches each post's view, `GET /view/k`: its count, everyone's likes with the
  viewer's own, and whether the viewer's is among them. The count shown is
  `count c v shown` (`Cairn.Optimistic.count`), and the view's liked moves a post only if it
  wasn't pressed this session (`seen`).

`cairn fuzz` checks it against a fake server that keeps the values and the other accounts' likes
(Fixture/Fuzz.lean, `Cairn.Fuzz.Server`), with replies failed before and lost after the server
acted. `receive`'s `blind` is the mutant Fixture/LikeMutant.lean catches: it takes a lost write
for a refused one and rolls back, which is wrong whenever the server applied the write before
the reply was lost.

Requests go to `127.0.0.1:9`, where nothing listens, so in the real app every write is lost and
read back on a backoff; the server is the fuzzer's, and conformance's: `cairn conformance` holds
the app's requests and answers them from it (Cairn's docs/conformance.md, "The world"). -/

@[expose] public section

namespace Fixture.Like
open Cairn Cairn.Optimistic

/-- How many posts have a Like button, keyed 1 to `posts`. -/
def posts : Nat := 4

def url (k : Nat) : String := s!"http://127.0.0.1:9/like/{k}"
def viewUrl (k : Nat) : String := s!"http://127.0.0.1:9/view/{k}"
def bit (v : Bool) : ByteArray := (if v then "1" else "0").toUTF8
def writeReq (k : Nat) (v : Bool) : Request := .http "PUT" (url k) [] (bit v) 5000
def readReq (k : Nat) : Request := .http "GET" (url k) [] .empty 5000
def viewReq (k : Nat) : Request := .http "GET" (viewUrl k) [] .empty 5000
def timerName (k : Nat) : String := s!"like-{k}"

/-- A view's body: the count and the viewer's like, `"17 1"`. -/
def viewBody (count : Nat) (liked : Bool) : ByteArray := s!"{count} {if liked then 1 else 0}".toUTF8

/-- A view's body read back: the count and the viewer's like. -/
def parseView (b : ByteArray) : Option (Nat × Bool) := do
  let s ← String.fromUTF8? b
  match s.splitOn " " with
  | [c, l] => return (← c.toNat?, l == "1")
  | _ => none

/-- What a request was sent for. -/
inductive Req where
  /-- A write the table asked for. -/
  | write (t : Ticket Nat)
  /-- A read back the table asked for. -/
  | read (t : Ticket Nat)
  /-- A view of post `k`. -/
  | view (k : Nat)
deriving Repr, DecidableEq, Inhabited

/-- A post's last view: the request it answered, its count and the viewer's like in it. -/
structure View where
  req : Nat
  count : Nat
  liked : Bool
deriving Repr, DecidableEq, Inhabited

/-- The likes: the table, what each request is for, the views, and the last rollback. -/
structure Likes where
  table : Table Nat Bool := .empty false (· == ·)
  reqs : Std.TreeMap Nat Req := {}
  views : Std.TreeMap Nat View := {}
  /-- The last rollback, in words. A press clears it. -/
  line : Option String := none
deriving Repr, BEq, Inhabited

/-- The likes, the next request id, and the effects to send. -/
abbrev Out := Likes × Nat × List Effect

/-- What a rollback says. -/
def say (k : Nat) (liked : Bool) : Reason → String
  | .refused why => s!"Couldn't {if liked then "unlike" else "like"} post {k}: {why}"
  | .notApplied => s!"Couldn't {if liked then "unlike" else "like"} post {k}: it never reached the server"

/-- Carry out the table's outputs, in order. -/
def perform (l : Likes) (n : Nat) : List (Optimistic.Out Nat Bool) → Out
  | [] => (l, n, [])
  | o :: os =>
    let (l, n, es) : Out := match o with
      | .write t v => ({ l with reqs := l.reqs.insert n (.write t) }, n + 1, [.request n (writeReq t.key v)])
      | .read t => ({ l with reqs := l.reqs.insert n (.read t) }, n + 1, [.request n (readReq t.key)])
      | .retryIn k ms => (l, n, [.setTimer (timerName k) ms])
      | .rolledBack k r => ({ l with line := some (say k (l.table.shown k) r) }, n, [])
    let (l, n, es') := perform l n os
    (l, n, es ++ es')

/-- Feed the table one input and carry out what it asks. -/
def feed (l : Likes) (n : Nat) (i : Input Nat Bool) : Out :=
  perform { l with table := (l.table.feed i).1 } n (l.table.feed i).2

/-- A press of post `k`'s Like. -/
def press (k : Nat) (l : Likes) (n : Nat) : Out := feed { l with line := none } n (.set k (!·))

/-- Refresh: a view of every post. -/
def refresh (l : Likes) (n : Nat) : Out :=
  let ks := List.range' 1 posts
  ({ l with reqs := ks.foldl (fun (m : Std.TreeMap Nat Req) k => m.insert (n + k - 1) (.view k)) l.reqs },
    n + posts, ks.map fun k => .request (n + k - 1) (viewReq k))

/-- A write's reply. `blind`: the mutant, which takes a lost write for a refused one. -/
def wrote (blind : Bool) (t : Ticket Nat) : Reply → Input Nat Bool
  | .http st _ _ =>
    if 200 ≤ st ∧ st < 300 then .acked t
    else if 400 ≤ st ∧ st < 500 then .refused t s!"the server said {st}"
    else if blind then .refused t s!"the server said {st}" else .lost t
  | _ => if blind then .refused t "no reply" else .lost t

/-- A read's reply. -/
def readBack (t : Ticket Nat) : Reply → Input Nat Bool
  | .http 200 _ b => if b == bit true then .read t true else if b == bit false then .read t false
    else .readFailed t
  | _ => .readFailed t

/-- A view's reply, request `id`: kept if it is newer than the post's last, and its liked fed as
`seen`. -/
def viewed (l : Likes) (n id k : Nat) : Reply → Out
  | .http 200 _ b =>
    match parseView b with
    | some (c, v) =>
      let newer : Bool := match l.views[k]? with
        | some old => old.req < id
        | none => true
      if newer then
        feed { l with views := l.views.insert k ⟨id, c, v⟩ } n (.seen k v)
      else (l, n, [])
    | none => (l, n, [])
  | _ => (l, n, [])

/-- The reply to request `id`, sent for `q`. -/
def answer (blind : Bool) (l : Likes) (n id : Nat) : Req → Reply → Out
  | .write t, r => feed l n (wrote blind t r)
  | .read t, r => feed l n (readBack t r)
  | .view k, r => viewed l n id k r

/-- A message from the world: a reply to a request of the likes, or a post's read-back timer. -/
def receive (blind : Bool := false) (l : Likes) (n : Nat) : Msg → Out
  | .reply id r =>
    match l.reqs[id]? with
    | some q => answer blind { l with reqs := l.reqs.erase id } n id q r
    | none => (l, n, [])
  | .timer name =>
    match (List.range' 1 posts).find? (timerName · == name) with
    | some k => feed l n (.retry k)
    | none => (l, n, [])
  | _ => (l, n, [])

/-! ## What is shown -/

/-- Whether post `k` shows liked. -/
def Likes.shown (l : Likes) (k : Nat) : Bool := l.table.shown k

/-- Post `k`'s count as shown: the last view's, with the viewer's like as shown
(`Cairn.Optimistic.count`). -/
def Likes.countOf (l : Likes) (k : Nat) : Nat :=
  let v := l.views[k]?.getD default
  count v.count v.liked (l.shown k)

/-- Whether post `k` waits on the server: a write in flight or in doubt. -/
def Likes.busy (l : Likes) (k : Nat) : Bool := l.table.inFlight k || l.table.inDoubt k

/-! ## Proofs -/

/-- The likes' invariant: the table compares with `==`, and every post at rest shows what the
server last confirmed (`Table.Calm`). -/
def Ok (l : Likes) : Prop := l.table.same = (· == ·) ∧ l.table.Calm

theorem perform_table (l : Likes) (n : Nat) (os : List (Optimistic.Out Nat Bool)) :
    (perform l n os).1.table = l.table := by
  induction os generalizing l n with
  | nil => rfl
  | cons o os ih =>
    simp only [perform]
    cases o <;> simp only [ih]

theorem feed_ok {l : Likes} (n : Nat) (i : Input Nat Bool) (h : Ok l) : Ok (feed l n i).1 := by
  unfold feed
  rw [Ok, perform_table]
  refine ⟨by rw [Table.feed_same]; exact h.1, Table.calm_feed _ ?_ h.2 i⟩
  rw [h.1]; exact Same.beq

theorem viewed_ok {l : Likes} (n id k : Nat) (r : Reply) (h : Ok l) : Ok (viewed l n id k r).1 := by
  unfold viewed
  split
  · split
    · simp only
      split <;> (split; exact feed_ok n _ h; exact h)
    · exact h
  · exact h

theorem answer_ok (blind : Bool) {l : Likes} (n id : Nat) (q : Req) (r : Reply) (h : Ok l) :
    Ok (answer blind l n id q r).1 := by
  cases q with
  | write t => exact feed_ok n _ h
  | read t => exact feed_ok n _ h
  | view k => exact viewed_ok n id k r h

theorem init_ok : Ok ({} : Likes) :=
  ⟨rfl, Table.calm_empty false _ Same.beq⟩

theorem press_ok (k : Nat) {l : Likes} (n : Nat) (h : Ok l) : Ok (press k l n).1 :=
  feed_ok (l := { l with line := none }) n _ h

theorem refresh_ok {l : Likes} (n : Nat) (h : Ok l) : Ok (refresh l n).1 := h

theorem receive_ok (blind : Bool) {l : Likes} (n : Nat) (m : Msg) (h : Ok l) :
    Ok (receive blind l n m).1 := by
  unfold receive
  split
  · split
    · exact answer_ok blind n _ _ _ h
    · exact h
  · split
    · exact feed_ok n _ h
    · exact h
  · exact h

/-- A post at rest shows what the server last confirmed. -/
theorem Ok.settled {l : Likes} (h : Ok l) {k : Nat} (hk : l.table.settled k = true) :
    l.shown k = l.table.server k := by
  have := h.2.settled hk
  rw [h.1] at this
  simpa [Likes.shown] using this

/-- The count shown is never below the viewer's own like, so never below zero. -/
theorem countOf_ge (l : Likes) (k : Nat) : ind (l.shown k) ≤ l.countOf k := count_ge _ _ _

end Fixture.Like
