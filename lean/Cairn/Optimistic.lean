module

public import Std.Data.TreeMap

/-! # Optimistic values: shown at once, then confirmed or rolled back

A `Table K V` holds values a person changes and a server keeps, keyed by `K` (a post's URI, an
account's DID). A change shows in the step it is made; the table then sends one write for it,
and the server's answer confirms it or rolls it back (docs/optimistic.md). Nothing here knows
about any particular server: the app turns the table's outputs into requests and the requests'
answers into its inputs.

Per key the table keeps an `Entry`:

* `server`, the last value the server confirmed: an acknowledged write, an authoritative read,
  or a view of a key never written this session;
* `want`, what the person asked for last. **This is what is shown** (`Table.shown`);
* `phase`: nothing outstanding (`idle`), a write in flight (`writing v`), a write whose answer
  was lost and a read in flight to settle it (`doubt v`), the same with the read failed and a
  retry due (`waiting v`), or a read checking a view that disagreed (`checking`);
* `seq`, the number of the key's last request: answers carry it (`Ticket`), and an answer whose
  number isn't the current one is stale and ignored. So a duplicated, late or superseded answer
  changes nothing.

The rules (`Entry.step`):

* **One write in flight per key.** A `set` while one is in flight, or in doubt, only changes
  `want`. When the write is answered, one write toward `want` is sent if `want` and `server`
  still differ (by the app's `same`, e.g. "liked or not, whichever record").
* **Refused** rolls the key back in that step: `want := server`, reported as `rolledBack` when
  what is shown changes.
* **Lost** (no answer: a timeout, a network failure, a 5xx) puts the key in doubt and sends a
  read. The read's answer settles it: the server holds the written value (acknowledged) or it
  doesn't (refused, `Reason.notApplied`). A failed read is retried on a backoff (1 s, doubling,
  at most 30 s, `retryIn`), never by writing again.
* **Views** (`seen`) move a key only if it has never been written this session. A written key
  that a view disagrees with, with nothing outstanding, gets a read (`checking`), whose answer
  is authoritative. So a stale view never undoes a confirmed write.
* **Counts** over a boolean value: `count c v w = c − [v] + [w]` (`count`).

Lookups and updates are O(log n) in the number of keys (`Std.TreeMap`).

Theorems here, for every table: `shown_set` (a set shows in its own step), `get_feed_ne` (an
input touches only its key), `feed_comm` (inputs for different keys commute: the same table,
the same outputs, in the other order), `refused_rollback` (a refusal shows `server` in its step),
`seen_written` (a view never moves a written key), `writes_le_sets` (never more writes than sets,
per key, for any sequence of inputs), and the count's arithmetic (`count_exact`, `count_ge`).
Convergence against a server, for any order of replies, is `Cairn.Optimistic.Server`; the claims
(`cairn^1100`–`cairn^1114`) are `Cairn.Optimistic.Claims`. -/

@[expose] public section

set_option linter.unusedSectionVars false

namespace Cairn.Optimistic

/-! ## Entries -/

/-- The first retry of a failed read, in milliseconds. -/
def firstBackoff : Nat := 1000

/-- The longest wait between retries. -/
def maxBackoff : Nat := 30000

/-- The next wait: double, at most `maxBackoff`. -/
def nextBackoff (ms : Nat) : Nat := min (2 * ms) maxBackoff

/-- What a key is waiting for. -/
inductive Phase (V : Type) where
  /-- Nothing outstanding. -/
  | idle
  /-- A write of `v` is in flight. -/
  | writing (v : V)
  /-- The write of `v` got no answer; a read is in flight to learn whether it was applied. -/
  | doubt (v : V)
  /-- The same, with that read failed; a `retry` sends the next. -/
  | waiting (v : V)
  /-- A view disagreed with a written key; a read is in flight to check it. -/
  | checking
deriving Repr, DecidableEq, Inhabited

namespace Phase
variable {V : Type}

def isIdle : Phase V → Bool
  | .idle => true
  | _ => false

/-- Whether a `set` may send a write now: nothing in flight or in doubt. -/
def isOpen : Phase V → Bool
  | .idle | .checking => true
  | _ => false

/-- The value of the write in flight or in doubt, if any. -/
def pending : Phase V → Option V
  | .writing v | .doubt v | .waiting v => some v
  | _ => none

end Phase

/-- One key's state. -/
structure Entry (V : Type) where
  /-- The last value the server confirmed. -/
  server : V
  /-- What the person asked for last: what is shown. -/
  want : V
  /-- Whether the person has set this key this session. -/
  written : Bool := false
  phase : Phase V := .idle
  /-- The number of the key's last request (0: none yet). -/
  seq : Nat := 0
  /-- The wait before the next retry of a failed read. -/
  backoff : Nat := firstBackoff
deriving Repr, DecidableEq

/-- A key the table hasn't heard of: `v` confirmed and shown. -/
def Entry.fresh {V : Type} (v : V) : Entry V := { server := v, want := v }

/-- Why a key was rolled back. -/
inductive Reason where
  /-- The server refused the write (a 4xx), for the reason the app gave. -/
  | refused (why : String)
  /-- The write's answer was lost, and the read that followed shows it wasn't applied. -/
  | notApplied
deriving Repr, DecidableEq, Inhabited

/-- What one key hears (`Input` without the key). -/
inductive Ev (V : Type) where
  | set (f : V → V)
  | acked (n : Nat)
  | refused (n : Nat) (why : String)
  | lost (n : Nat)
  | read (n : Nat) (v : V)
  | readFailed (n : Nat)
  | retry
  | seen (v : V)

/-- What one key asks for (`Out` without the key). -/
inductive Act (V : Type) where
  | write (n : Nat) (v : V)
  | read (n : Nat)
  | retryIn (ms : Nat)
  | rolledBack (r : Reason)
deriving Repr, DecidableEq

namespace Entry
variable {V : Type} (same : V → V → Bool)

/-- Send a write of `want`, as request `seq + 1`. -/
def send (e : Entry V) : Entry V × List (Act V) :=
  ({ e with phase := .writing e.want, seq := e.seq + 1 }, [.write (e.seq + 1) e.want])

/-- Send a read, as request `seq + 1`, waiting in `ph`. -/
def ask (e : Entry V) (ph : Phase V) : Entry V × List (Act V) :=
  ({ e with phase := ph, seq := e.seq + 1 }, [.read (e.seq + 1)])

/-- The server's value is known (`e.server`): rest if `want` is the same, else write toward it. -/
def settle (e : Entry V) : Entry V × List (Act V) :=
  if same e.want e.server then ({ e with phase := .idle, backoff := firstBackoff }, [])
  else send { e with backoff := firstBackoff }

/-- Show the server's value again, saying why if what is shown changes. -/
def rollback (e : Entry V) (r : Reason) : Entry V × List (Act V) :=
  ({ e with want := e.server, phase := .idle, backoff := firstBackoff },
    if same e.want e.server then [] else [.rolledBack r])

/-- **One key's step.** -/
def step (e : Entry V) : Ev V → Entry V × List (Act V)
  | .set f =>
    if e.phase.isOpen && !same (f e.want) e.server then
      send { e with want := f e.want, written := true }
    else ({ e with want := f e.want, written := true }, [])
  | .acked n =>
    match e.phase with
    | .writing w => if n = e.seq then settle same { e with server := w } else (e, [])
    | _ => (e, [])
  | .refused n why =>
    match e.phase with
    | .writing _ => if n = e.seq then rollback same e (.refused why) else (e, [])
    | _ => (e, [])
  | .lost n =>
    match e.phase with
    | .writing w => if n = e.seq then ask { e with backoff := firstBackoff } (.doubt w) else (e, [])
    | _ => (e, [])
  | .read n v =>
    if n = e.seq then
      match e.phase with
      | .doubt w =>
        if same v w then settle same { e with server := v }
        else rollback same { e with server := v } .notApplied
      | .checking => ({ e with server := v, want := v, phase := .idle }, [])
      | _ => (e, [])
    else (e, [])
  | .readFailed n =>
    if n = e.seq then
      match e.phase with
      | .doubt w =>
        ({ e with phase := .waiting w, backoff := nextBackoff e.backoff }, [.retryIn e.backoff])
      | .checking => ({ e with phase := .idle }, [])
      | _ => (e, [])
    else (e, [])
  | .retry =>
    match e.phase with
    | .waiting w => ask e (.doubt w)
    | _ => (e, [])
  | .seen v =>
    if !e.written && e.phase.isIdle then ({ e with server := v, want := v }, [])
    else if e.phase.isIdle && !same v e.want then ask e .checking else (e, [])

end Entry

/-! ## Tables -/

/-- A request's ticket: the key it is about and its number among that key's requests. The app
keeps its own request ids and maps each to the ticket it was sent for (docs/optimistic.md). -/
structure Ticket (K : Type) where
  key : K
  seq : Nat
deriving Repr, DecidableEq, Inhabited

/-- What the table hears. -/
inductive Input (K V : Type) where
  /-- The person changes key `k` to `f` of what is shown (`f : V → V`, so "like" on a value
  already liked can keep its record). -/
  | set (k : K) (f : V → V)
  /-- The write was applied (a 2xx). -/
  | acked (t : Ticket K)
  /-- The write was refused and not applied (a 4xx), for `why`. -/
  | refused (t : Ticket K) (why : String)
  /-- The write got no answer (a timeout, a network failure, a 5xx): it may or may not have
  been applied. -/
  | lost (t : Ticket K)
  /-- An authoritative read's answer: what the server holds for the key now. -/
  | read (t : Ticket K) (v : V)
  /-- A read got no usable answer. -/
  | readFailed (t : Ticket K)
  /-- The backoff timer `retryIn` asked for came due. -/
  | retry (k : K)
  /-- A value in a view the app fetched (a list, a page), which may be stale. -/
  | seen (k : K) (v : V)

/-- What the table asks the app to do. -/
inductive Out (K V : Type) where
  /-- Send a write of `v` for `t.key`, and answer it with `t`. -/
  | write (t : Ticket K) (v : V)
  /-- Read `t.key`'s value from the server, authoritatively, and answer with `t`. -/
  | read (t : Ticket K)
  /-- Feed `retry k` in `ms` milliseconds (a timer). -/
  | retryIn (k : K) (ms : Nat)
  /-- `k` was rolled back; say so in words. -/
  | rolledBack (k : K) (r : Reason)
deriving Repr, DecidableEq

namespace Input
variable {K V : Type}

def key : Input K V → K
  | .set k _ | .retry k | .seen k _ => k
  | .acked t | .refused t _ | .lost t | .read t _ | .readFailed t => t.key

def ev : Input K V → Ev V
  | .set _ f => .set f
  | .acked t => .acked t.seq
  | .refused t why => .refused t.seq why
  | .lost t => .lost t.seq
  | .read t v => .read t.seq v
  | .readFailed t => .readFailed t.seq
  | .retry _ => .retry
  | .seen _ v => .seen v

end Input

/-- An entry's action, as the table's output for key `k`. -/
def Act.out {K V : Type} (k : K) : Act V → Out K V
  | .write n v => .write ⟨k, n⟩ v
  | .read n => .read ⟨k, n⟩
  | .retryIn ms => .retryIn k ms
  | .rolledBack r => .rolledBack k r

/-- **The table.** `dflt` is the value of a key it hasn't heard of; `same a b` says whether two
values mean the same to the server (for a like: liked or not, whichever record). `same` should
be an equivalence (`Same`); the theorems that need it say so. -/
structure Table (K V : Type) [Ord K] where
  entries : Std.TreeMap K (Entry V) compare := {}
  dflt : V
  same : V → V → Bool

namespace Table
variable {K V : Type} [Ord K]

/-- An empty table. -/
def empty (dflt : V) (same : V → V → Bool) : Table K V := { dflt, same }

/-- Key `k`'s entry: O(log n). -/
def get (t : Table K V) (k : K) : Entry V := t.entries[k]?.getD (Entry.fresh t.dflt)

/-- **What is shown** for `k`: `want`. -/
def shown (t : Table K V) (k : K) : V := (t.get k).want

/-- The last value the server confirmed for `k`. -/
def server (t : Table K V) (k : K) : V := (t.get k).server

/-- A write for `k` is in flight. -/
def inFlight (t : Table K V) (k : K) : Bool :=
  match (t.get k).phase with
  | .writing _ => true
  | _ => false

/-- `k`'s last write got no answer, and isn't settled yet. -/
def inDoubt (t : Table K V) (k : K) : Bool :=
  match (t.get k).phase with
  | .doubt _ | .waiting _ => true
  | _ => false

/-- Nothing outstanding for `k`: no write in flight or in doubt, no read checking a view. -/
def settled (t : Table K V) (k : K) : Bool := (t.get k).phase.isIdle

/-- Whether the person set `k` this session. -/
def written (t : Table K V) (k : K) : Bool := (t.get k).written

/-- **One step**: the input's key's entry steps, and its actions become outputs. O(log n). -/
def feed (t : Table K V) (i : Input K V) : Table K V × List (Out K V) :=
  let r := (t.get i.key).step t.same i.ev
  ({ t with entries := t.entries.insert i.key r.1 }, r.2.map (Act.out i.key))

/-- Feed inputs in order; the outputs in order. -/
def run (t : Table K V) : List (Input K V) → Table K V × List (Out K V)
  | [] => (t, [])
  | i :: is =>
    let r := t.feed i
    let r' := r.1.run is
    (r'.1, r.2 ++ r'.2)

/-- Every key with nothing outstanding. O(n). -/
def allSettled (t : Table K V) : Bool := t.entries.all fun _ e => e.phase.isIdle

/-- The number of keys the table holds. -/
def size (t : Table K V) : Nat := t.entries.size

instance [Repr K] [Repr V] : Repr (Table K V) where
  reprPrec t _ := "Table " ++ repr t.entries.toList

/-- Two tables are `==` when they hold the same entries and default; `same` is a function and
isn't compared. So an app's state that holds a table can derive `BEq` for its tests. -/
instance [BEq K] [DecidableEq V] : BEq (Table K V) where
  beq a b := a.entries.toList == b.entries.toList && a.dflt == b.dflt

/-- An empty table of `default`s, with every value the same as every other: for `deriving
Inhabited`. A real table is `Table.empty`. -/
instance [Inhabited V] : Inhabited (Table K V) := ⟨.empty default fun _ _ => true⟩

end Table

/-! ## Counts -/

/-- `[b]`: one if `b`. -/
def ind (b : Bool) : Nat := if b then 1 else 0

/-- **A count over a boolean key**: `c` and `v` are the count and the person's own value from
the latest view (the count includes the person's own exactly when `v`), `w` is what is shown:
`c − [v] + [w]`. Never below zero (a `Nat`, `count_ge`), and exact whenever the view is
consistent (`count_exact`). -/
def count (c : Nat) (v w : Bool) : Nat := c - ind v + ind w

/-! ## Theorems -/

/-- `same` is an equivalence. -/
structure Same {V : Type} (same : V → V → Bool) : Prop where
  refl : ∀ a, same a a = true
  symm : ∀ a b, same a b = true → same b a = true
  trans : ∀ a b c, same a b = true → same b c = true → same a c = true

/-- Equality, as `same`. -/
theorem Same.beq {V : Type} [BEq V] [LawfulBEq V] : Same (fun a b : V => a == b) :=
  ⟨fun a => beq_self_eq_true a, fun a b h => by simp only [beq_iff_eq] at h ⊢; exact h.symm,
    fun a b c h1 h2 => by simp only [beq_iff_eq] at h1 h2 ⊢; exact h1.trans h2⟩

theorem count_exact (c : Nat) (v w : Bool) (h : ind v ≤ c) :
    (count c v w : Int) = (c : Int) - ind v + ind w := by
  simp only [count]; omega

theorem count_ge (c : Nat) (v w : Bool) : ind w ≤ count c v w := by
  simp only [count]; omega

/-- **Counts once settled.** A view's count is other people's `o` plus the person's own `[v]`.
When the key shows the server's value `r` (a settled key does, `Server.converges`), the count
shown is `o + [r]`: exactly the server's count when no one else acted since the view. -/
theorem count_view (o : Nat) (v r : Bool) : count (o + ind v) v r = o + ind r := by
  simp only [count]; omega

namespace Table
variable {K V : Type} [Ord K] [Std.TransOrd K] [Std.LawfulEqOrd K] [DecidableEq K]

theorem get_insert (t : Table K V) (k j : K) (e : Entry V) :
    ({ t with entries := t.entries.insert k e } : Table K V).get j =
      if k = j then e else t.get j := by
  simp only [get, Std.TreeMap.getElem?_insert]
  by_cases h : k = j
  · subst h; simp only [Std.ReflCmp.compare_self, ↓reduceIte, Option.getD_some]
  · have : compare k j ≠ .eq := fun h' => h (Std.LawfulEqCmp.eq_of_compare h')
    simp only [this, ↓reduceIte, h]

/-- What `feed` does to any key: the input's key steps; every other key is as it was. -/
theorem get_feed (t : Table K V) (i : Input K V) (k : K) :
    (t.feed i).1.get k = if i.key = k then ((t.get i.key).step t.same i.ev).1 else t.get k := by
  simp only [feed, get_insert]

theorem get_feed_self (t : Table K V) (i : Input K V) :
    (t.feed i).1.get i.key = ((t.get i.key).step t.same i.ev).1 := by
  simp only [get_feed, ↓reduceIte]

/-- **An input touches only its key.** -/
theorem get_feed_ne (t : Table K V) (i : Input K V) {k : K} (h : i.key ≠ k) :
    (t.feed i).1.get k = t.get k := by
  simp only [get_feed, h, ↓reduceIte]

@[simp] theorem feed_same (t : Table K V) (i : Input K V) : (t.feed i).1.same = t.same := rfl
@[simp] theorem feed_dflt (t : Table K V) (i : Input K V) : (t.feed i).1.dflt = t.dflt := rfl

theorem feed_out (t : Table K V) (i : Input K V) :
    (t.feed i).2 = ((t.get i.key).step t.same i.ev).2.map (Act.out i.key) := rfl

/-- **A set shows in its own step**: after `set k f`, `k` shows `f` of what it showed. -/
theorem shown_set (t : Table K V) (k : K) (f : V → V) :
    (t.feed (.set k f)).1.shown k = f (t.shown k) := by
  have := get_feed_self t (.set k f)
  simp only [Input.key] at this
  simp only [shown, this, Input.ev, Entry.step]
  split <;> rfl

/-- **Inputs for different keys commute**: in either order the table is the same at every key,
and each input's outputs are the ones it gives alone, so the two orders' outputs are the same
two lists, swapped. -/
theorem feed_comm (t : Table K V) (i j : Input K V) (h : i.key ≠ j.key) :
    (∀ k, ((t.feed i).1.feed j).1.get k = ((t.feed j).1.feed i).1.get k) ∧
      ((t.feed i).1.feed j).2 = (t.feed j).2 ∧ ((t.feed j).1.feed i).2 = (t.feed i).2 := by
  have hj : (t.feed i).1.get j.key = t.get j.key := get_feed_ne t i h
  have hi : (t.feed j).1.get i.key = t.get i.key := get_feed_ne t j (Ne.symm h)
  refine ⟨fun k => ?_, ?_, ?_⟩
  · simp only [get_feed, feed_same, hj, hi]
    by_cases h1 : j.key = k
    · subst h1; simp only [↓reduceIte, h]
    · by_cases h2 : i.key = k
      · subst h2; simp only [h1, ↓reduceIte]
      · simp only [h1, h2, ↓reduceIte]
  · simp only [feed_out, feed_same, hj]
  · simp only [feed_out, feed_same, hi]

/-- **A refusal rolls back in its step**: when `k`'s write `n` is in flight, `refused` for it
leaves `k` showing the server's value, which is unchanged. -/
theorem refused_rollback (t : Table K V) (k : K) (n : Nat) (why : String) (w : V)
    (hp : (t.get k).phase = .writing w) (hn : n = (t.get k).seq) :
    (t.feed (.refused ⟨k, n⟩ why)).1.shown k = t.server k ∧
      (t.feed (.refused ⟨k, n⟩ why)).1.server k = t.server k ∧
      (t.feed (.refused ⟨k, n⟩ why)).1.settled k = true := by
  have := get_feed_self t (.refused ⟨k, n⟩ why)
  subst hn
  simp only [Input.key] at this
  simp only [shown, server, settled, this, Input.ev, Entry.step, hp, ↓reduceIte,
    Entry.rollback, Phase.isIdle, and_self]

/-- **A view never moves a written key**: `seen` leaves what a key written this session shows,
and the server value it holds, as they were. -/
theorem seen_written (t : Table K V) (k : K) (v : V) (hw : t.written k = true) :
    (t.feed (.seen k v)).1.shown k = t.shown k ∧ (t.feed (.seen k v)).1.server k = t.server k := by
  have := get_feed_self t (.seen k v)
  simp only [Input.key] at this
  simp only [written] at hw
  simp only [shown, server, this, Input.ev, Entry.step, hw, Bool.not_true, Bool.false_and,
    Bool.false_eq_true, ↓reduceIte]
  split <;> exact ⟨rfl, rfl⟩

/-- `feed` reads the table only through `get`, `same` and `dflt`: tables equal at every key
step alike. (`TreeMap`s holding the same entries can differ in shape; nothing here sees it.) -/
theorem feed_ext (t u : Table K V) (h : ∀ k, t.get k = u.get k) (hs : t.same = u.same)
    (i : Input K V) : (∀ k, (t.feed i).1.get k = (u.feed i).1.get k) ∧ (t.feed i).2 = (u.feed i).2 := by
  refine ⟨fun k => ?_, ?_⟩
  · simp only [get_feed, h, hs]
  · simp only [feed_out, h, hs]

end Table

/-! ### Never more writes than sets -/

namespace Entry
variable {V : Type} (same : V → V → Bool)

/-- The writes among an entry's actions. -/
def writes (as : List (Act V)) : Nat := as.countP fun | .write .. => true | _ => false

/-- Writes `w` within sets `s`; and when the write outstanding isn't what is shown, a set is
yet to be written. -/
def Budget (e : Entry V) (s w : Nat) : Prop :=
  w ≤ s ∧ ∀ x, e.phase.pending = some x → same e.want x = false → w < s

/-- How many sets an event is. -/
def Ev.sets {V : Type} : Ev V → Nat
  | .set _ => 1
  | _ => 0

theorem budget_step (hs : Same same) (e : Entry V) (s w : Nat) (h : Budget same e s w)
    (ev : Ev V) :
    Budget same (e.step same ev).1 (s + Ev.sets ev) (w + writes (e.step same ev).2) := by
  obtain ⟨h1, h2⟩ := h
  have hrefl := hs.refl
  cases ev <;> simp only [step, Ev.sets, send, ask, settle, rollback] <;> (repeat' split) <;>
    simp_all [writes, Budget, Phase.pending]
  all_goals first
    | omega
    | exact ⟨by omega, fun _ _ _ => by omega⟩
    | (rename_i w0 _ _ hvw hwv
       have : same e.want w0 = false := by
         cases hx : same e.want w0
         · rfl
         · rw [hs.trans _ _ _ hx (hs.symm _ _ hvw)] at hwv; cases hwv
       have := h2 this; omega)
    | (intro x hx; cases hp : e.phase <;> simp_all [Phase.isIdle])

end Entry

namespace Table
variable {K V : Type} [Ord K] [Std.TransOrd K] [Std.LawfulEqOrd K] [DecidableEq K]

/-- The sets of `k` among some inputs. -/
def setsFor (k : K) (is : List (Input K V)) : Nat :=
  is.countP fun | .set j _ => decide (j = k) | _ => false

/-- The writes for `k` among some outputs. -/
def writesFor (k : K) (os : List (Out K V)) : Nat :=
  os.countP fun | .write t _ => decide (t.key = k) | _ => false

theorem writesFor_map (k j : K) (as : List (Act V)) :
    writesFor k (as.map (Act.out j)) = if j = k then Entry.writes as else 0 := by
  induction as with
  | nil => simp only [writesFor, List.map_nil, List.countP_nil, Entry.writes]; split <;> rfl
  | cons a as ih =>
    simp only [writesFor, List.map_cons, List.countP_cons] at ih ⊢
    rw [ih]
    cases a <;> by_cases h : j = k <;>
      simp only [Act.out, Entry.writes, List.countP_cons, h, decide_true, decide_false,
        ↓reduceIte, Nat.add_zero, Bool.false_eq_true]

theorem budget_feed (t : Table K V) (hs : Same t.same) (s w : K → Nat)
    (h : ∀ k, Entry.Budget t.same (t.get k) (s k) (w k)) (i : Input K V) (k : K) :
    Entry.Budget t.same ((t.feed i).1.get k) (s k + setsFor k [i])
      (w k + writesFor k (t.feed i).2) := by
  rw [get_feed, feed_out, writesFor_map]
  by_cases hk : i.key = k
  · subst hk
    simp only [↓reduceIte]
    have := Entry.budget_step t.same hs _ _ _ (h i.key) i.ev
    have e : setsFor i.key [i] = Entry.Ev.sets i.ev := by
      cases i <;> simp only [setsFor, List.countP_cons, List.countP_nil, Input.key, Input.ev,
        Entry.Ev.sets, decide_true, ↓reduceIte, Nat.zero_add, Bool.false_eq_true]
    rw [e]; exact this
  · have e : setsFor k [i] = 0 := by
      cases i <;> simp_all [setsFor, Input.key]
    simp only [hk, ↓reduceIte, e, Nat.add_zero]; exact h k

theorem budget_run :
    ∀ (is : List (Input K V)) (t : Table K V) (s w : K → Nat), Same t.same →
      (∀ k, Entry.Budget t.same (t.get k) (s k) (w k)) →
      ∀ k, Entry.Budget t.same ((t.run is).1.get k) (s k + setsFor k is)
        (w k + writesFor k (t.run is).2)
  | [], t, s, w, _, h, k => by simpa [run, setsFor, writesFor] using h k
  | i :: is, t, s, w, hs, h, k => by
    have h1 := budget_feed t hs s w h i
    have := budget_run is (t.feed i).1 (fun k => s k + setsFor k [i])
      (fun k => w k + writesFor k (t.feed i).2) hs h1 k
    have es : setsFor k (i :: is) = setsFor k [i] + setsFor k is := by
      simp only [setsFor, List.countP_cons, List.countP_nil]; omega
    simp only [run, feed_same] at this ⊢
    rw [es]
    simp only [writesFor, List.countP_append] at this ⊢
    rw [← Nat.add_assoc, ← Nat.add_assoc]
    exact this

/-- **Never more writes than sets.** From an empty table, for any sequence of inputs (any
answers, in any order, duplicated or stale), the writes the table asks for `k` never outnumber
the person's sets of `k`. -/
theorem writes_le_sets (dflt : V) (same : V → V → Bool) (hs : Same same)
    (is : List (Input K V)) (k : K) :
    writesFor k ((empty dflt same : Table K V).run is).2 ≤ setsFor k is := by
  have := budget_run is (empty dflt same) (fun _ => 0) (fun _ => 0) hs
    (fun k => ⟨Nat.le_refl 0, fun x hx => by
      simp only [empty, get, Std.TreeMap.getElem?_emptyc, Option.getD_none, Entry.fresh,
        Phase.pending, reduceCtorEq] at hx⟩) k
  simpa using this.1

end Table

/-! ### At rest, a key shows the server's value -/

namespace Entry
variable {V : Type} (same : V → V → Bool)

/-- With no write in flight or in doubt (`idle`, or `checking` a view), what is shown is the
server's last confirmed value (by `same`). -/
def Calm (e : Entry V) : Prop := e.phase.isOpen = true → same e.want e.server = true

theorem calm_step (hs : Same same) (e : Entry V) (h : Calm same e) (ev : Ev V) :
    Calm same (e.step same ev).1 := by
  have hrefl := hs.refl
  unfold Calm at h ⊢
  cases ev <;> simp only [step, send, ask, settle, rollback] <;> (repeat' split) <;>
    simp_all [Phase.isOpen]
  all_goals (cases hp : e.phase <;> simp_all [Phase.isIdle])

end Entry

namespace Table
variable {K V : Type} [Ord K] [Std.TransOrd K] [Std.LawfulEqOrd K] [DecidableEq K]

/-- Every key at rest shows the server's last confirmed value. -/
def Calm (t : Table K V) : Prop := ∀ k, Entry.Calm t.same (t.get k)

theorem calm_empty (dflt : V) (same : V → V → Bool) (hs : Same same) :
    (empty dflt same : Table K V).Calm := by
  intro k _
  simp only [empty, get, Std.TreeMap.getElem?_emptyc, Option.getD_none, Entry.fresh]
  exact hs.refl dflt

/-- **At rest, a key shows the server's value**, after any input. -/
theorem calm_feed (t : Table K V) (hs : Same t.same) (h : t.Calm) (i : Input K V) :
    (t.feed i).1.Calm := by
  intro k
  rw [feed_same, get_feed]
  split
  · subst_vars; exact Entry.calm_step t.same hs _ (h _) _
  · exact h k

/-- A settled key shows what the table last heard from the server. -/
theorem Calm.settled {t : Table K V} (h : t.Calm) {k : K} (hk : t.settled k = true) :
    t.same (t.shown k) (t.server k) = true := by
  apply h k
  unfold Table.settled at hk
  revert hk
  cases (t.get k).phase <;> simp [Phase.isIdle, Phase.isOpen]

end Table

end Cairn.Optimistic
