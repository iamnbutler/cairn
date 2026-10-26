module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.Optimistic.Server

/-! # Optimistic values: the claims

`Cairn.Optimistic`'s claims (`cairn^1100`–`cairn^1114`, docs/optimistic.md), stated over a
harness `machine` whose state is the server model's `World` at keys `Nat` and boolean values
(liked or not), with `same` equality. Its moves are every way the person, the server and the
network act (`Cairn.Optimistic.Server`): the person flips a key (^1100); the server handles or
refuses a packet (^1101, ^1102); the network delivers or loses one, before or after the server
handled it (^1103, ^1104); the backoff timer fires (^1105); a view is fetched (^1106). A move's
key `i` picks the `i`-th packet in the network (nothing if there is none). Any sequence of these
is any interleaving of sets and replies, so an invariant of the machine holds after every one.

The invariants:

| Id | Claim | Theorem |
|---|---|---|
| ^1107 | a set shows in its own step | `Table.shown_set` |
| ^1108 | at most one write in flight per key | `World.Ok.oneWrite` |
| ^1109 | never more writes than sets, per key | `World.Ok.writes_le_sets`, `Table.writes_le_sets` |
| ^1110 | a refusal rolls back in its step | `Table.refused_rollback` |
| ^1111 | once settled, a key shows what the server holds, for any order of replies | `World.Ok.converges` |
| ^1112 | inputs for different keys commute | `Table.feed_comm` |
| ^1113 | a settled count is the view's others plus the server's own, never below zero | `World.Ok.count`, `count_ge` |
| ^1114 | a view never moves a key written this session | `Table.seen_written` |

^1107, ^1110, ^1112 and ^1114 hold of every table; the harness states them of the table in every
reachable state. The theorems are general (any key type with a lawful order, any value type,
any `same` that is an equivalence); the harness instantiates them. Not imported by `Cairn` (the
host links that); `CairnAll` imports it, so the ledger reads it. -/

@[expose] public section

namespace Cairn.Optimistic.Claims
open Cairn Cairn.Claims Cairn.Optimistic

/-- The harness's world: keys are numbers, values booleans. -/
abbrev W := World Nat Bool

/-- The packet the `i`-th place in the network holds, if any. -/
def pick (s : W) (i : Nat) : Option (Nat × Pkt Bool) := s.net[i]?

/-- Act on the `i`-th packet, if there is one. -/
def onPkt (s : W) (i : Nat) (f : W → Nat → Pkt Bool → W) : W :=
  match pick s i with
  | some (k, p) => f s k p
  | none => s

theorem onPkt_ok {s : W} (h : s.Ok) (i : Nat) {f : W → Nat → Pkt Bool → W}
    (hf : ∀ k p, (f s k p).Ok) : (onPkt s i f).Ok := by
  unfold onPkt; split
  · exact hf _ _
  · exact h

theorem onPkt_eq {s : W} (i : Nat) {f : W → Nat → Pkt Bool → W} {P : W → Prop}
    (hf : ∀ k p, P (f s k p)) (hs : P s) : P (onPkt s i f) := by
  unfold onPkt; split
  · exact hf _ _
  · exact hs

theorem serve_table (s : W) (k : Nat) (p : Pkt Bool) : (s.serve k p).table = s.table := by
  unfold World.serve; split
  · split <;> rfl
  · rfl

theorem refuse_table (s : W) (k : Nat) (p : Pkt Bool) :
    (s.refuse k p).table = s.table ∧ (s.refuse k p).srv = s.srv := by
  unfold World.refuse; split
  · split <;> exact ⟨rfl, rfl⟩
  · exact ⟨rfl, rfl⟩

theorem deliver_srv (s : W) (k : Nat) (p : Pkt Bool) : (s.deliver k p).srv = s.srv := by
  unfold World.deliver; split
  · split <;> rfl
  · rfl

theorem lose_srv (s : W) (k : Nat) (p : Pkt Bool) : (s.lose k p).srv = s.srv := by
  unfold World.lose; split
  · split <;> rfl
  · rfl

/-! ## The moves -/

move ^1100 press (s : W) (k : Nat) "Set a value" where
  does "The person flips key k (likes or unlikes it)."
  sees "Key k shows the new value in that step, whatever is in flight."
  on press
    apply := s.press k (fun b => !b)
    post s' := s'.table.shown k = !(s.table.shown k)
    sound := by intro s k; exact Table.shown_set s.table k _

move ^1101 serve (s : W) (i : Nat) "The server handles a request" where
  does "The server handles the i-th packet in the network: applies a write (its answer becomes acked) or answers a read with what it holds."
  sees "Nothing changes on screen: the table hears nothing until an answer arrives."
  on press
    apply := onPkt s i World.serve
    post s' := s'.table = s.table
    sound := by intro s i; exact onPkt_eq i (P := fun t => t.table = s.table) (serve_table s) rfl

move ^1102 refuse (s : W) (i : Nat) "The server refuses a request" where
  does "The server refuses the i-th packet in the network, and changes nothing."
  sees "Neither the screen nor the server changes; the refusal is on its way."
  on press
    apply := onPkt s i World.refuse
    post s' := s'.table = s.table ∧ s'.srv = s.srv
    sound := by
      intro s i
      exact onPkt_eq i (P := fun t => t.table = s.table ∧ t.srv = s.srv) (refuse_table s)
        ⟨rfl, rfl⟩

move ^1103 deliver (s : W) (i : Nat) "An answer arrives" where
  does "The network delivers the i-th packet, an answer or a view, to the table."
  sees "The table settles, rolls back, retries or takes the view; the server is unchanged."
  on press
    apply := onPkt s i World.deliver
    post s' := s'.srv = s.srv
    sound := by intro s i; exact onPkt_eq i (P := fun t => t.srv = s.srv) (deliver_srv s) rfl

move ^1104 lose (s : W) (i : Nat) "A request or answer is lost" where
  does "The network loses the i-th packet, before or after the server handled it; the table hears lost (a write) or readFailed (a read)."
  sees "A lost write puts its key in doubt and sends a read; the server is unchanged."
  on press
    apply := onPkt s i World.lose
    post s' := s'.srv = s.srv
    sound := by intro s i; exact onPkt_eq i (P := fun t => t.srv = s.srv) (lose_srv s) rfl

move ^1105 retry (s : W) (k : Nat) "A retry comes due" where
  does "Key k's backoff timer fires."
  sees "A key waiting after a failed read sends the next read; the server is unchanged."
  on press
    apply := s.retry k
    post s' := s'.srv = s.srv
    sound := by intro s k; rfl

move ^1106 look (s : W) (k : Nat) "A view is fetched" where
  does "The app fetches a view of key k: what the server holds now, delivered whenever (^1103)."
  sees "Nothing changes until the view arrives."
  on press
    apply := s.look k
    post s' := s'.table = s.table
    sound := by intro s k; rfl

def machine : Machine W := { init := World.start false (fun a b => a == b), moves := moves% }

/-- The server model's invariant, with `same` the harness's equality. -/
def Good (s : W) : Prop := s.Ok ∧ s.table.same = fun a b => a == b

theorem init_good : Good machine.init := ⟨World.Ok.start false _ Same.beq, rfl⟩

theorem onPkt_good {s : W} (h : Good s) (i : Nat) {f : W → Nat → Pkt Bool → W}
    (hf : ∀ k p, (f s k p).Ok) (hs : ∀ k p, (f s k p).table.same = s.table.same) :
    Good (onPkt s i f) :=
  onPkt_eq i (P := Good) (fun k p => ⟨hf k p, (hs k p).trans h.2⟩) h

/-- Every move keeps `Good`. -/
theorem update_good : ∀ s a, Good s → Good (machine.update s a).1 :=
  machine.preserves <|
    Move.all_cons (press.preserves _ fun _ k h => ⟨h.1.press k _, h.2⟩)
      (Move.all_cons (serve.preserves _ fun s i h =>
        onPkt_good h i h.1.serve (World.serve_same s))
      (Move.all_cons (refuse.preserves _ fun s i h =>
        onPkt_good h i h.1.refuse (World.refuse_same s))
      (Move.all_cons (deliver.preserves _ fun s i h =>
        onPkt_good h i h.1.deliver (World.deliver_same s))
      (Move.all_cons (lose.preserves _ fun s i h =>
        onPkt_good h i h.1.lose (World.lose_same s))
      (Move.all_cons (retry.preserves _ fun _ k h => ⟨h.1.retry k, h.2⟩)
      (Move.all_cons (look.preserves _ fun _ k h => ⟨h.1.look k, h.2⟩) Move.all_nil))))))

theorem Good.converges {s : W} (h : Good s) (k : Nat) (hk : s.table.settled k = true) :
    s.table.shown k = s.reg k := by
  have := h.1.converges k hk
  rw [h.2] at this; simpa using this

/-! ## The invariants -/

invariant ^1107 setShows "A set shows in its own step" for machine where
  does "Whatever is in flight or in doubt, setting a key to f of what it shows makes it show exactly that in the same step: what is shown is want, and a set changes want at once."
  holds s := ∀ (k : Nat) (f : Bool → Bool), (s.table.feed (.set k f)).1.shown k = f (s.table.shown k)
  init := fun k f => Table.shown_set _ k f
  step := fun _ _ _ k f => Table.shown_set _ k f

invariant ^1108 oneWrite "At most one write in flight per key" for machine where
  does "For every key, at most one write is in the network, before or after the server handled it: a set while one is in flight only changes what is shown."
  holds s := Good s ∧ ∀ k, (World.at s.net k).countP Pkt.isWrite ≤ 1
  init := ⟨init_good, init_good.1.oneWrite⟩
  step := fun s a h => ⟨update_good s a h.1, (update_good s a h.1).1.oneWrite⟩

invariant ^1109 writesWithinSets "Never more writes than sets" for machine where
  does "For every key, the writes the table has sent never outnumber the person's sets of it, whatever answers came back in whatever order: a lost write is read back, never sent again blind."
  holds s := Good s ∧ ∀ k, s.writes.count k ≤ s.sets.count k
  init := ⟨init_good, init_good.1.writes_le_sets⟩
  step := fun s a h => ⟨update_good s a h.1, (update_good s a h.1).1.writes_le_sets⟩

invariant ^1110 refusalRollsBack "A refusal rolls back in its step" for machine where
  does "When a key's write in flight is refused, the key shows the server's last confirmed value in that step, that value is unchanged, and nothing is outstanding for the key."
  holds s := ∀ (k n : Nat) (why : String) (w : Bool), (s.table.get k).phase = .writing w →
    n = (s.table.get k).seq →
    (s.table.feed (.refused ⟨k, n⟩ why)).1.shown k = s.table.server k ∧
      (s.table.feed (.refused ⟨k, n⟩ why)).1.server k = s.table.server k ∧
      (s.table.feed (.refused ⟨k, n⟩ why)).1.settled k = true
  init := fun k n why w hp hn => Table.refused_rollback _ k n why w hp hn
  step := fun _ _ _ k n why w hp hn => Table.refused_rollback _ k n why w hp hn

invariant ^1111 converges "Settled keys show what the server holds" for machine where
  does "Against a server that is a register per key with idempotent writes, for any sequence of sets and any interleaving of replies (each acknowledged, refused, or lost before or after the server applied it, delivered in any order, with views fetched at any time), every key with nothing in flight and nothing in doubt shows what the server holds. So once every reply is in, every key does."
  holds s := Good s ∧ ∀ k, s.table.settled k = true → s.table.shown k = s.reg k
  init := ⟨init_good, init_good.converges⟩
  step := fun s a h => ⟨update_good s a h.1, (update_good s a h.1).converges⟩

invariant ^1112 commute "Replies for different keys commute" for machine where
  does "Two inputs about different keys, in either order, leave the table the same at every key, and each gives the outputs it gives alone, so the two orders' outputs are the same two lists swapped."
  holds s := ∀ i j : Input Nat Bool, i.key ≠ j.key →
    (∀ k, ((s.table.feed i).1.feed j).1.get k = ((s.table.feed j).1.feed i).1.get k) ∧
      ((s.table.feed i).1.feed j).2 = (s.table.feed j).2 ∧
      ((s.table.feed j).1.feed i).2 = (s.table.feed i).2
  init := fun i j h => Table.feed_comm _ i j h
  step := fun _ _ _ i j h => Table.feed_comm _ i j h

invariant ^1113 counts "A settled count is the server's" for machine where
  does "For a view whose count is other people's o plus the person's own [v], a settled key shows o + [what the server holds]: exactly the server's count when no one else acted since the view. The count shown, c − [v] + [shown], is never below zero, and never below the person's own [shown]."
  holds s := Good s ∧ ∀ (k o : Nat) (v : Bool), s.table.settled k = true →
    count (o + ind v) v (s.table.shown k) = o + ind (s.reg k) ∧
      ind (s.table.shown k) ≤ count (o + ind v) v (s.table.shown k)
  init := ⟨init_good, fun k o v hk => ⟨init_good.1.count init_good.2 k hk o v, count_ge _ _ _⟩⟩
  step := fun s a h => ⟨update_good s a h.1, fun k o v hk =>
    ⟨(update_good s a h.1).1.count (update_good s a h.1).2 k hk o v, count_ge _ _ _⟩⟩

invariant ^1114 viewKeepsWritten "A view never moves a written key" for machine where
  does "A value in a view the app fetched, which may be stale (fetched before a write, or from a server that hasn't indexed it yet), never changes what a key written this session shows, or its confirmed value."
  holds s := ∀ (k : Nat) (v : Bool), s.table.written k = true →
    (s.table.feed (.seen k v)).1.shown k = s.table.shown k ∧
      (s.table.feed (.seen k v)).1.server k = s.table.server k
  init := fun k v hw => Table.seen_written _ k v hw
  step := fun _ _ _ k v hw => Table.seen_written _ k v hw

def claimInfos : List ClaimInfo := claims%

end Cairn.Optimistic.Claims
