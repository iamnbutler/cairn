module

public import Cairn.Optimistic

/-! # Optimistic values against a server: convergence for any order of replies

The abstract server `Cairn.Optimistic` is proved against (docs/optimistic.md, "The server
model"). A `World` is a table, the server (a register per key, `reg`), and the network: every
request the table sent and every answer on its way back, as a bag (`net`) that any step may take
any element of. The steps (`World.press`, `serve`, `refuse`, `deliver`, `lose`, `retry`,
`look`) are every way the person, the server and the network can act:

* the person sets a key (`press`);
* the server handles a request: applies a write (its answer is `acked`) or answers a read with
  what it holds (`serve`), or refuses either (`refuse`): a refused write changes nothing;
* the network delivers an answer to the table (`deliver`), or loses a request or an answer,
  before or after the server handled it: the table hears `lost` or `readFailed` (`lose`);
* the backoff timer fires (`retry`), and the app fetches a view of a key (`look`), which may
  arrive after the key has changed.

Writes are idempotent: applying one sets the register to its value, so applying it once or
twice is the same. A write is applied at most once here (`serve` takes the request out of the
bag), which loses nothing: a second application would set the same value.

**`Ok`** is the invariant, kept by every step (`Ok.press` … `Ok.look`); from it:

* `Ok.converges`: **a settled key shows what the server holds** (by `same`). So once nothing is
  in flight or in doubt, whatever order the replies came in, every key shows the server's value;
* `Ok.oneWrite`: at most one write in flight per key;
* `Ok.writes_le_sets`: never more writes sent for a key than the person's sets of it;
* `Ok.count`: a settled key's count is the view's other people plus the server's own.

Every step changes one key; `Ok` is per key (`KeyOk`), and a step at one key leaves every other
key's part as it was (`World.at_*`), which is also why replies for different keys commute
(`Table.feed_comm`). -/

@[expose] public section

set_option linter.unusedSectionVars false

namespace Cairn.Optimistic

/-- A packet about one key, in the network. Numbers are the key's request numbers. -/
inductive Pkt (V : Type) where
  /-- A write the server hasn't handled. -/
  | write (n : Nat) (v : V)
  /-- A read the server hasn't handled. -/
  | read (n : Nat)
  /-- The server applied write `n`; the answer is on its way. -/
  | acked (n : Nat)
  /-- The server refused write `n` and didn't apply it. -/
  | refused (n : Nat)
  /-- The server answered read `n` with `v`, what it held then. -/
  | answer (n : Nat) (v : V)
  /-- The server refused read `n`. -/
  | failed (n : Nat)
  /-- A view of the key, saying `v`. -/
  | view (v : V)
deriving Repr, DecidableEq

namespace Pkt
variable {V : Type}

def seq? : Pkt V → Option Nat
  | .write n _ | .read n | .acked n | .refused n | .answer n _ | .failed n => some n
  | .view _ => none

/-- A write, before or after the server handled it: a write in flight. -/
def isWrite : Pkt V → Bool
  | .write .. | .acked _ | .refused _ => true
  | _ => false

/-- Whether the packet is request `n` of its key. -/
def cur (n : Nat) (p : Pkt V) : Bool := p.seq? == some n

end Pkt

/-- A read `n`, before or after the server handled it; an answer says `r`. -/
def Readish {V : Type} (n : Nat) (r : V) (p : Pkt V) : Prop :=
  p = .read n ∨ p = .answer n r ∨ p = .failed n

/-- What a key's packets with its current number say, by phase. `cur` is those packets, `r` the
server's value. -/
def PhaseOk {V : Type} (same : V → V → Bool) (e : Entry V) (r : V) (cur : List (Pkt V)) : Prop :=
  match e.phase with
  | .idle => cur = [] ∧ e.server = r ∧ same e.want e.server = true
  | .checking => (∃ p, cur = [p] ∧ Readish e.seq r p) ∧ e.server = r ∧
      same e.want e.server = true ∧ e.written = true
  | .writing w => ((cur = [.write e.seq w] ∧ r = e.server) ∨ (cur = [.acked e.seq] ∧ r = w) ∨
      (cur = [.refused e.seq] ∧ r = e.server)) ∧ e.written = true
  | .doubt _ => (∃ p, cur = [p] ∧ Readish e.seq r p) ∧ e.written = true
  | .waiting _ => cur = [] ∧ e.written = true

/-- **One key is consistent** with the server's value `r` and its packets `ps`: no packet is
from a request not yet made; every write in flight is the current request; a key never written
is idle and every view of it says `r`; and the current packets fit the phase. -/
structure KeyOk {V : Type} (same : V → V → Bool) (e : Entry V) (r : V) (ps : List (Pkt V)) :
    Prop where
  le : ∀ p ∈ ps, ∀ n, p.seq? = some n → n ≤ e.seq
  writes : ∀ p ∈ ps, p.isWrite = true → p.seq? = some e.seq
  unwritten : e.written = false → e.phase = .idle ∧ ∀ v, Pkt.view v ∈ ps → v = r
  phase : PhaseOk same e r (ps.filter (Pkt.cur e.seq))

/-- The person, the table, the server and the network. -/
structure World (K V : Type) [Ord K] where
  table : Table K V
  /-- The server: a register per key (`reg`). -/
  srv : Std.TreeMap K V compare := {}
  /-- Every request and answer on its way, keyed. -/
  net : List (K × Pkt V) := []
  /-- The key of every set, in order. -/
  sets : List K := []
  /-- The key of every write the table sent, in order. -/
  writes : List K := []

namespace World
variable {K V : Type} [Ord K] [DecidableEq K] [DecidableEq V]

/-- What the server holds for `k`. -/
def reg (w : World K V) (k : K) : V := w.srv[k]?.getD w.table.dflt

/-- The packets about `k`. -/
def «at» (net : List (K × Pkt V)) (k : K) : List (Pkt V) :=
  net.filterMap fun q => if q.1 = k then some q.2 else none

/-- A table output, as the packet it puts in the network. -/
def pktOf : Out K V → Option (K × Pkt V)
  | .write t v => some (t.key, .write t.seq v)
  | .read t => some (t.key, .read t.seq)
  | _ => none

/-- A table output's key, if it is a write. -/
def writeOf : Out K V → Option K
  | .write t _ => some t.key
  | _ => none

/-- The table hears `i`; what it sends goes into the network. -/
def feed (w : World K V) (i : Input K V) : World K V :=
  let r := w.table.feed i
  { w with table := r.1, net := w.net ++ r.2.filterMap pktOf,
           writes := w.writes ++ r.2.filterMap writeOf }

/-- The person sets `k` to `f` of what it shows. -/
def press (w : World K V) (k : K) (f : V → V) : World K V :=
  { w.feed (.set k f) with sets := w.sets ++ [k] }

/-- The server handles packet `(k, p)`: applies a write, or answers a read with what it holds. -/
def serve (w : World K V) (k : K) (p : Pkt V) : World K V :=
  if (k, p) ∈ w.net then
    match p with
    | .write n v => { w with srv := w.srv.insert k v, net := w.net.erase (k, p) ++ [(k, .acked n)] }
    | .read n => { w with net := w.net.erase (k, p) ++ [(k, .answer n (w.reg k))] }
    | _ => w
  else w

/-- The server refuses packet `(k, p)`, and changes nothing. -/
def refuse (w : World K V) (k : K) (p : Pkt V) : World K V :=
  if (k, p) ∈ w.net then
    match p with
    | .write n _ => { w with net := w.net.erase (k, p) ++ [(k, .refused n)] }
    | .read n => { w with net := w.net.erase (k, p) ++ [(k, .failed n)] }
    | _ => w
  else w

/-- The input the table hears when `(k, p)` arrives. -/
def heard (k : K) : Pkt V → Option (Input K V)
  | .acked n => some (.acked ⟨k, n⟩)
  | .refused n => some (.refused ⟨k, n⟩ "refused")
  | .answer n v => some (.read ⟨k, n⟩ v)
  | .failed n => some (.readFailed ⟨k, n⟩)
  | .view v => some (.seen k v)
  | _ => none

/-- The input the table hears when `(k, p)` is lost on the way. -/
def missed (k : K) : Pkt V → Option (Input K V)
  | .write n _ | .acked n | .refused n => some (.lost ⟨k, n⟩)
  | .read n | .answer n _ | .failed n => some (.readFailed ⟨k, n⟩)
  | .view _ => none

/-- The network delivers answer `(k, p)` to the table. -/
def deliver (w : World K V) (k : K) (p : Pkt V) : World K V :=
  if (k, p) ∈ w.net then
    match heard k p with
    | some i => ({ w with net := w.net.erase (k, p) } : World K V).feed i
    | none => w
  else w

/-- The network loses `(k, p)`, before or after the server handled it. -/
def lose (w : World K V) (k : K) (p : Pkt V) : World K V :=
  if (k, p) ∈ w.net then
    match missed k p with
    | some i => ({ w with net := w.net.erase (k, p) } : World K V).feed i
    | none => { w with net := w.net.erase (k, p) }
  else w

/-- `k`'s backoff timer fires. -/
def retry (w : World K V) (k : K) : World K V := w.feed (.retry k)

/-- The app fetches a view of `k`: what the server holds now, delivered whenever. -/
def look (w : World K V) (k : K) : World K V :=
  { w with net := w.net ++ [(k, .view (w.reg k))] }

/-- Every step. -/
inductive Step : World K V → World K V → Prop where
  | press (w : World K V) (k : K) (f : V → V) : Step w (w.press k f)
  | serve (w : World K V) (k : K) (p : Pkt V) : Step w (w.serve k p)
  | refuse (w : World K V) (k : K) (p : Pkt V) : Step w (w.refuse k p)
  | deliver (w : World K V) (k : K) (p : Pkt V) : Step w (w.deliver k p)
  | lose (w : World K V) (k : K) (p : Pkt V) : Step w (w.lose k p)
  | retry (w : World K V) (k : K) : Step w (w.retry k)
  | look (w : World K V) (k : K) : Step w (w.look k)

/-- Some steps, in order. -/
inductive Reach : World K V → World K V → Prop where
  | refl (w : World K V) : Reach w w
  | tail {a b c : World K V} : Reach a b → Step b c → Reach a c

/-- A world at the start: an empty table, a server holding `dflt` for every key (`srv` empty),
nothing in the network. -/
def start (dflt : V) (same : V → V → Bool) : World K V := { table := .empty dflt same }

end World

/-- **The invariant**: `same` is an equivalence, and every key is consistent, with writes within
sets. -/
structure World.Ok {K V : Type} [Ord K] [DecidableEq K] [DecidableEq V] (w : World K V) : Prop where
  same : Same w.table.same
  key : ∀ k, KeyOk w.table.same (w.table.get k) (w.reg k) (World.at w.net k)
  budget : ∀ k, Entry.Budget w.table.same (w.table.get k) (w.sets.count k) (w.writes.count k)

/-! ## One key -/

namespace Pkt
variable {V : Type}

/-- An entry's action, as the packet it puts in the network. -/
def ofAct : Act V → Option (Pkt V)
  | .write n v => some (.write n v)
  | .read n => some (.read n)
  | _ => none

/-- What the key hears when `p` arrives. -/
def heard : Pkt V → Option (Ev V)
  | .acked n => some (.acked n)
  | .refused n => some (.refused n "refused")
  | .answer n v => some (.read n v)
  | .failed n => some (.readFailed n)
  | .view v => some (.seen v)
  | _ => none

/-- What the key hears when `p` is lost. -/
def missed : Pkt V → Option (Ev V)
  | .write n _ | .acked n | .refused n => some (.lost n)
  | .read n | .answer n _ | .failed n => some (.readFailed n)
  | .view _ => none

end Pkt

namespace KeyOk
variable {V : Type} [DecidableEq V] {same : V → V → Bool}

/-- The key hears `ev`, with `ps` its packets after the one that brought `ev` left. -/
def after (same : V → V → Bool) (e : Entry V) (ps : List (Pkt V)) (ev : Ev V) : List (Pkt V) :=
  ps ++ (e.step same ev).2.filterMap Pkt.ofAct

/-- The packets of a key after its current request left: none from a later request, no
write, none current. -/
structure Rest (m : Nat) (ps : List (Pkt V)) : Prop where
  le : ∀ q ∈ ps, ∀ n, q.seq? = some n → n ≤ m
  noWrite : ∀ q ∈ ps, q.isWrite = false
  noCur : ps.filter (Pkt.cur m) = []

theorem PhaseOk.small {e : Entry V} {r : V} {cur : List (Pkt V)} (h : PhaseOk same e r cur) :
    cur = [] ∨ ∃ x, cur = [x] := by
  unfold PhaseOk at h
  split at h
  · exact .inl h.1
  · obtain ⟨⟨p, hp, -⟩, -⟩ := h; exact .inr ⟨p, hp⟩
  · obtain ⟨h | h | h, -⟩ := h <;> exact .inr ⟨_, h.1⟩
  · obtain ⟨⟨p, hp, -⟩, -⟩ := h; exact .inr ⟨p, hp⟩
  · exact .inl h.1

theorem cur_mem {ps : List (Pkt V)} {n : Nat} {p : Pkt V} (hp : p ∈ ps) (hc : p.cur n = true) :
    p ∈ ps.filter (Pkt.cur n) := List.mem_filter.2 ⟨hp, hc⟩

/-- A current packet is the only one. -/
theorem single {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {p : Pkt V}
    (hp : p ∈ ps) (hc : p.cur e.seq = true) : ps.filter (Pkt.cur e.seq) = [p] := by
  have hm := cur_mem hp hc
  rcases PhaseOk.small h.phase with h1 | ⟨x, h1⟩
  · rw [h1] at hm; cases hm
  · rw [h1] at hm ⊢; simp only [List.mem_singleton] at hm; rw [hm]

theorem isWrite_cur {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {q : Pkt V}
    (hq : q ∈ ps) (hw : q.isWrite = true) : q.cur e.seq = true := by
  simp only [Pkt.cur, h.writes q hq hw, beq_self_eq_true]

/-- With the current packet gone, the rest. -/
theorem rest_erase {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {p : Pkt V}
    (hp : p ∈ ps) (hc : p.cur e.seq = true) : Rest e.seq (ps.erase p) := by
  have hs := single h hp hc
  have hnc : (ps.erase p).filter (Pkt.cur e.seq) = [] := by
    rw [← List.erase_filter, hs, List.erase_cons_head]
  refine ⟨fun q hq => h.le q (List.mem_of_mem_erase hq), fun q hq => ?_, hnc⟩
  cases hw : q.isWrite
  · rfl
  · have := cur_mem hq (isWrite_cur h (List.mem_of_mem_erase hq) hw)
    rw [hnc] at this; cases this

/-- With nothing current, all of them. -/
theorem rest_self {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps)
    (hnc : ps.filter (Pkt.cur e.seq) = []) : Rest e.seq ps := by
  refine ⟨h.le, fun q hq => ?_, hnc⟩
  cases hw : q.isWrite
  · rfl
  · have := cur_mem hq (isWrite_cur h hq hw)
    rw [hnc] at this; cases this

/-- **A new request**: the rest, and the request's one packet. -/
theorem fresh {e e' : Entry V} {r : V} {ps : List (Pkt V)} (hle : ∀ q ∈ ps, ∀ n, q.seq? = some n → n ≤ e.seq)
    (hnw : ∀ q ∈ ps, q.isWrite = false) (hs : e'.seq = e.seq + 1)
    {q : Pkt V} (hq : q.seq? = some e'.seq) (hph : PhaseOk same e' r [q]) (hw : e'.written = true) :
    KeyOk same e' r (ps ++ [q]) := by
  have hf : (ps ++ [q]).filter (Pkt.cur e'.seq) = [q] := by
    rw [List.filter_append, List.filter_eq_nil_iff.2 (fun x hx => ?_)]
    · simp only [List.filter_cons, Pkt.cur, hq, beq_self_eq_true, ↓reduceIte, List.filter_nil,
        List.nil_append]
    · cases hx' : x.seq? with
      | none => simp only [Pkt.cur, hx', reduceCtorEq, beq_iff_eq, not_false_eq_true]
      | some m =>
        have := hle x hx m hx'
        simp only [Pkt.cur, hx', hs]; simp only [beq_iff_eq, Option.some.injEq]; omega
  refine ⟨fun x hx m hm => ?_, fun x hx hxw => ?_, fun hw' => (by rw [hw] at hw'; cases hw'), by rw [hf]; exact hph⟩
  · rcases List.mem_append.1 hx with hx | hx
    · have := hle x hx m hm; omega
    · simp only [List.mem_singleton] at hx; subst hx; rw [hq] at hm; cases hm; omega
  · rcases List.mem_append.1 hx with hx | hx
    · rw [hnw x hx] at hxw; cases hxw
    · simp only [List.mem_singleton] at hx; subst hx; exact hq

/-- **Nothing new**: the rest, with nothing current. -/
theorem quiet {e e' : Entry V} {r : V} {ps : List (Pkt V)} (h : Rest e.seq ps) (hs : e'.seq = e.seq)
    (hph : PhaseOk same e' r [])
    (hu : e'.written = false → e'.phase = .idle ∧ ∀ v, Pkt.view v ∈ ps → v = r) :
    KeyOk same e' r ps := by
  refine ⟨fun x hx m hm => hs ▸ h.le x hx m hm, fun x hx hxw => ?_, hu, by rw [hs, h.noCur]; exact hph⟩
  rw [h.noWrite x hx] at hxw; cases hxw

/-- A packet that isn't current can go. -/
theorem erase_stale {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {p : Pkt V}
    (hc : p.cur e.seq = false) : KeyOk same e r (ps.erase p) := by
  have hf : (ps.erase p).filter (Pkt.cur e.seq) = ps.filter (Pkt.cur e.seq) := by
    rw [← List.erase_filter, List.erase_of_not_mem]
    intro hm; rw [(List.mem_filter.1 hm).2] at hc; cases hc
  refine ⟨fun q hq => h.le q (List.mem_of_mem_erase hq),
    fun q hq => h.writes q (List.mem_of_mem_erase hq),
    fun hw => ⟨(h.unwritten hw).1, fun v hv => (h.unwritten hw).2 v (List.mem_of_mem_erase hv)⟩,
    by rw [hf]; exact h.phase⟩

/-- Nothing in flight: no write among the packets, and the server's value is confirmed. -/
theorem open_facts {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps)
    (ho : e.phase.isOpen = true) :
    (∀ q ∈ ps, q.isWrite = false) ∧ e.server = r ∧ same e.want e.server = true := by
  have hph := h.phase
  unfold PhaseOk at hph
  split at hph
  next hp =>
    refine ⟨fun q hq => ?_, hph.2⟩
    cases hw : q.isWrite
    · rfl
    · have := cur_mem hq (isWrite_cur h hq hw); rw [hph.1] at this; cases this
  next hp =>
    obtain ⟨⟨p, hp1, hp2⟩, h2, h3, -⟩ := hph
    refine ⟨fun q hq => ?_, h2, h3⟩
    cases hw : q.isWrite
    · rfl
    · have := cur_mem hq (isWrite_cur h hq hw); rw [hp1] at this
      simp only [List.mem_singleton] at this; subst this
      rcases hp2 with rfl | rfl | rfl <;> simp [Pkt.isWrite] at hw
  all_goals (rename_i hp; rw [hp] at ho; simp [Phase.isOpen] at ho)

/-- A write in flight is the current request, and the key is writing it. -/
theorem write_cases {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {p : Pkt V}
    (hp : p ∈ ps) (hw : p.isWrite = true) :
    p.cur e.seq = true ∧ e.written = true ∧ ∃ w, e.phase = .writing w ∧
      ((p = .write e.seq w ∧ r = e.server) ∨ (p = .acked e.seq ∧ r = w) ∨
        (p = .refused e.seq ∧ r = e.server)) := by
  have hc := isWrite_cur h hp hw
  have hs := single h hp hc
  have hph := h.phase; rw [hs] at hph
  unfold PhaseOk at hph
  split at hph
  next => simp at hph
  next =>
    obtain ⟨⟨q, hq1, hq2⟩, -⟩ := hph; simp at hq1; subst hq1
    rcases hq2 with rfl | rfl | rfl <;> simp [Pkt.isWrite] at hw
  next w hw' =>
    obtain ⟨h1, h2⟩ := hph
    refine ⟨hc, h2, w, hw', ?_⟩
    rcases h1 with ⟨h1, h3⟩ | ⟨h1, h3⟩ | ⟨h1, h3⟩ <;> simp at h1 <;> subst h1 <;> simp [h3]
  next =>
    obtain ⟨⟨q, hq1, hq2⟩, -⟩ := hph; simp at hq1; subst hq1
    rcases hq2 with rfl | rfl | rfl <;> simp [Pkt.isWrite] at hw
  next => simp at hph

/-- A current read, before or after the server: the key is checking or in doubt. -/
theorem read_cases {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {p : Pkt V}
    (hp : p ∈ ps) (hc : p.cur e.seq = true) (hw : p.isWrite = false) :
    Readish e.seq r p ∧ e.written = true ∧
      ((e.phase = .checking ∧ e.server = r ∧ same e.want e.server = true) ∨
        ∃ w, e.phase = .doubt w) := by
  have hs := single h hp hc
  have hph := h.phase; rw [hs] at hph
  unfold PhaseOk at hph
  split at hph
  next => simp at hph
  next hph' =>
    obtain ⟨⟨q, hq1, hq2⟩, h2, h3, h4⟩ := hph; simp at hq1; subst hq1
    exact ⟨hq2, h4, .inl ⟨hph', h2, h3⟩⟩
  next w hw' =>
    obtain ⟨h1, -⟩ := hph
    rcases h1 with ⟨h1, -⟩ | ⟨h1, -⟩ | ⟨h1, -⟩ <;> simp at h1 <;> subst h1 <;> simp [Pkt.isWrite] at hw
  next w hph' =>
    obtain ⟨⟨q, hq1, hq2⟩, h2⟩ := hph; simp at hq1; subst hq1
    exact ⟨hq2, h2, .inr ⟨w, hph'⟩⟩
  next => simp at hph

/-- The server's value `r` is known: rest, or write toward `want`. -/
theorem settle_ok (_hs : Same same) {e : Entry V} {r : V} {ps : List (Pkt V)} (h : Rest e.seq ps)
    (hw : e.written = true) (hr : e.server = r) :
    KeyOk same (Entry.settle same e).1 r (ps ++ (Entry.settle same e).2.filterMap Pkt.ofAct) := by
  unfold Entry.settle
  split
  · rename_i hsw
    simp only [List.filterMap_nil, List.append_nil]
    exact quiet h rfl ⟨rfl, hr, hsw⟩ (fun hw' => by simp [hw] at hw')
  · simp only [Entry.send, List.filterMap_cons, List.filterMap_nil, Pkt.ofAct]
    exact fresh h.le h.noWrite rfl rfl ⟨.inl ⟨rfl, hr.symm⟩, hw⟩ hw

/-- Back to the server's value `r`. -/
theorem rollback_ok (hs : Same same) {e : Entry V} {r : V} {ps : List (Pkt V)} (h : Rest e.seq ps)
    (hw : e.written = true) (hr : e.server = r) (why : Reason) :
    KeyOk same (Entry.rollback same e why).1 r
      (ps ++ (Entry.rollback same e why).2.filterMap Pkt.ofAct) := by
  have : (Entry.rollback same e why).2.filterMap Pkt.ofAct = [] := by
    simp only [Entry.rollback]; split <;> rfl
  rw [this, List.append_nil]
  exact quiet h rfl ⟨rfl, hr, hs.refl _⟩ (fun hw' => by simp [Entry.rollback, hw] at hw')

/-- A read's failure, current or stale. -/
theorem readFailed_ok {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {p : Pkt V}
    (hp : p ∈ ps) {n : Nat} (hn : p.seq? = some n) (hw : p.isWrite = false) :
    KeyOk same (e.step same (.readFailed n)).1 r (after same e (ps.erase p) (.readFailed n)) := by
  unfold after
  by_cases hc : p.cur e.seq = true
  · have hne : n = e.seq := by simpa [Pkt.cur, hn] using hc
    subst hne
    have hr := rest_erase h hp hc
    obtain ⟨-, hwr, hph⟩ := read_cases h hp hc hw
    rcases hph with ⟨hph, hsr, hsw⟩ | ⟨w, hph⟩
    · simp only [Entry.step, hph, ↓reduceIte, List.filterMap_nil, List.append_nil]
      exact quiet hr rfl ⟨rfl, hsr, hsw⟩ (fun hw' => by simp [hwr] at hw')
    · simp only [Entry.step, hph, ↓reduceIte, List.filterMap_cons, List.filterMap_nil, Pkt.ofAct,
        List.append_nil]
      exact quiet hr rfl ⟨rfl, hwr⟩ (fun hw' => by simp [hwr] at hw')
  · have hne : n ≠ e.seq := by intro he; subst he; simp [Pkt.cur, hn] at hc
    simp only [Entry.step, hne, ↓reduceIte, List.filterMap_nil, List.append_nil]
    exact erase_stale h (by simpa using hc)

/-- A write's answer lost: in doubt, and a read. -/
theorem lost_ok {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {p : Pkt V}
    (hp : p ∈ ps) {n : Nat} (hn : p.seq? = some n) (hw : p.isWrite = true) :
    KeyOk same (e.step same (.lost n)).1 r (after same e (ps.erase p) (.lost n)) := by
  obtain ⟨hc, hwr, w, hph, -⟩ := write_cases h hp hw
  have hne : n = e.seq := by simpa [Pkt.cur, hn] using hc
  subst hne
  have hr := rest_erase h hp hc
  unfold after
  simp only [Entry.step, hph, ↓reduceIte, Entry.ask, List.filterMap_cons, List.filterMap_nil,
    Pkt.ofAct]
  exact fresh hr.le hr.noWrite rfl rfl ⟨⟨_, rfl, .inl rfl⟩, hwr⟩ hwr

theorem press (_hs : Same same) {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps)
    (f : V → V) : KeyOk same (e.step same (.set f)).1 r (after same e ps (.set f)) := by
  unfold after
  by_cases hc : (e.phase.isOpen && !same (f e.want) e.server) = true
  · simp only [Entry.step, hc, ↓reduceIte, Entry.send, List.filterMap_cons, List.filterMap_nil,
      Pkt.ofAct]
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hc
    obtain ⟨hnw, hsr, -⟩ := open_facts h hc.1
    refine fresh h.le hnw rfl rfl ?_ rfl
    exact ⟨.inl ⟨rfl, hsr.symm⟩, rfl⟩
  · simp only [Entry.step, hc, Bool.false_eq_true, ↓reduceIte, List.filterMap_nil, List.append_nil]
    refine ⟨h.le, h.writes, fun hw => (by cases hw), ?_⟩
    have hph := h.phase
    unfold PhaseOk at hph ⊢
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true, not_and,
      Bool.not_eq_false] at hc
    split at hph
    next hp =>
      simp only [hp]
      exact ⟨hph.1, hph.2.1, hc (by simp [hp, Phase.isOpen])⟩
    next hp =>
      simp only [hp]
      exact ⟨hph.1, hph.2.1, hc (by simp [hp, Phase.isOpen]), trivial⟩
    next w hp => simp only [hp]; exact ⟨hph.1, trivial⟩
    next w hp => simp only [hp]; exact ⟨hph.1, trivial⟩
    next w hp => simp only [hp]; exact ⟨hph.1, trivial⟩

theorem retry (_hs : Same same) {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) :
    KeyOk same (e.step same .retry).1 r (after same e ps .retry) := by
  unfold after
  cases hp : e.phase with
  | waiting w =>
    simp only [Entry.step, hp, Entry.ask, List.filterMap_cons, List.filterMap_nil, Pkt.ofAct]
    have hph := h.phase
    unfold PhaseOk at hph; rw [hp] at hph
    refine fresh h.le (rest_self h hph.1).noWrite rfl rfl ?_ hph.2
    exact ⟨⟨_, rfl, .inl rfl⟩, hph.2⟩
  | _ => simp only [Entry.step, hp, List.filterMap_nil, List.append_nil]; exact h

theorem look {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) :
    KeyOk same e r (ps ++ [.view r]) := by
  have hf : (ps ++ [Pkt.view r]).filter (Pkt.cur e.seq) = ps.filter (Pkt.cur e.seq) := by
    simp [List.filter_append, Pkt.cur, Pkt.seq?]
  refine ⟨fun q hq => ?_, fun q hq => ?_, fun hw => ⟨(h.unwritten hw).1, fun v hv => ?_⟩,
    by rw [hf]; exact h.phase⟩
  · rcases List.mem_append.1 hq with hq | hq
    · exact h.le q hq
    · simp only [List.mem_singleton] at hq; subst hq; simp [Pkt.seq?]
  · rcases List.mem_append.1 hq with hq | hq
    · exact h.writes q hq
    · simp only [List.mem_singleton] at hq; subst hq; simp [Pkt.isWrite]
  · rcases List.mem_append.1 hv with hv | hv
    · exact (h.unwritten hw).2 v hv
    · simp only [List.mem_singleton, Pkt.view.injEq] at hv; exact hv

theorem deliver (hs : Same same) {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps)
    {p : Pkt V} (hp : p ∈ ps) {ev : Ev V} (hev : p.heard = some ev) :
    KeyOk same (e.step same ev).1 r (after same e (ps.erase p) ev) := by
  cases p with
  | write n v => simp [Pkt.heard] at hev
  | read n => simp [Pkt.heard] at hev
  | acked n =>
    simp only [Pkt.heard, Option.some.injEq] at hev; subst hev
    obtain ⟨hc, hw, w, hph, hk⟩ := write_cases h hp rfl
    have hn : n = e.seq := by simpa [Pkt.cur, Pkt.seq?] using hc
    subst hn
    have hrw : r = w := by
      rcases hk with ⟨h1, -⟩ | ⟨-, h1⟩ | ⟨h1, -⟩ <;> first | exact h1 | cases h1
    unfold after
    simp only [Entry.step, hph, ↓reduceIte]
    exact settle_ok hs (rest_erase h hp hc) hw hrw.symm
  | refused n =>
    simp only [Pkt.heard, Option.some.injEq] at hev; subst hev
    obtain ⟨hc, hw, w, hph, hk⟩ := write_cases h hp rfl
    have hn : n = e.seq := by simpa [Pkt.cur, Pkt.seq?] using hc
    subst hn
    have hrs : r = e.server := by
      rcases hk with ⟨h1, -⟩ | ⟨h1, -⟩ | ⟨-, h1⟩ <;> first | exact h1 | cases h1
    unfold after
    simp only [Entry.step, hph, ↓reduceIte]
    exact rollback_ok hs (rest_erase h hp hc) hw hrs.symm _
  | answer n v =>
    simp only [Pkt.heard, Option.some.injEq] at hev; subst hev
    unfold after
    by_cases hc : (Pkt.answer n v).cur e.seq = true
    · have hn : n = e.seq := by simpa [Pkt.cur, Pkt.seq?] using hc
      subst hn
      have hr := rest_erase h hp hc
      obtain ⟨hrd, hw, hph⟩ := read_cases h hp hc rfl
      have hv : v = r := by
        rcases hrd with h1 | h1 | h1 <;> simp at h1; exact h1
      subst hv
      rcases hph with ⟨hph, -, -⟩ | ⟨w, hph⟩
      · simp only [Entry.step, hph, ↓reduceIte, List.filterMap_nil, List.append_nil]
        exact quiet hr rfl ⟨rfl, rfl, hs.refl _⟩ (fun hw' => by simp [hw] at hw')
      · simp only [Entry.step, hph, ↓reduceIte]
        split
        · exact settle_ok hs (e := { e with server := v, phase := .doubt w }) hr hw rfl
        · exact rollback_ok hs (e := { e with server := v, phase := .doubt w }) hr hw rfl _
    · have hne : n ≠ e.seq := by intro he; subst he; simp [Pkt.cur, Pkt.seq?] at hc
      simp only [Entry.step, hne, ↓reduceIte, List.filterMap_nil, List.append_nil]
      exact erase_stale h (by simpa using hc)
  | failed n =>
    simp only [Pkt.heard, Option.some.injEq] at hev; subst hev
    exact readFailed_ok h hp rfl rfl
  | view v =>
    simp only [Pkt.heard, Option.some.injEq] at hev; subst hev
    have h' := erase_stale h (p := .view v) (by simp [Pkt.cur, Pkt.seq?])
    have hvr : e.written = false → v = r := fun hw => (h.unwritten hw).2 v hp
    unfold after
    by_cases h1 : (!e.written && e.phase.isIdle) = true
    · simp only [Entry.step, h1, ↓reduceIte, List.filterMap_nil, List.append_nil]
      simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h1
      have hidle : e.phase = .idle := by
        cases hp' : e.phase <;> simp_all [Phase.isIdle]
      have hph := h'.phase; unfold PhaseOk at hph; rw [hidle] at hph
      obtain rfl := hvr h1.1
      refine ⟨h'.le, h'.writes, fun _ => h'.unwritten h1.1, ?_⟩
      show PhaseOk same { e with server := v, want := v } v _
      unfold PhaseOk; simp only [hidle]
      refine ⟨hph.1, ?_⟩; simp [hs.refl]
    · simp only [Entry.step, h1, Bool.false_eq_true, ↓reduceIte]
      split
      · rename_i h2
        simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h1 h2
        have hidle : e.phase = .idle := by
          cases hp' : e.phase <;> simp_all [Phase.isIdle]
        have hwr : e.written = true := by
          cases hw : e.written
          · simp [hw, hidle, Phase.isIdle] at h1
          · rfl
        obtain ⟨hnw, hsr, hsw⟩ := open_facts h' (by simp [hidle, Phase.isOpen])
        simp only [Entry.ask, List.filterMap_cons, List.filterMap_nil, Pkt.ofAct]
        exact fresh h'.le hnw rfl rfl ⟨⟨_, rfl, .inl rfl⟩, hsr, hsw, hwr⟩ hwr
      · simp only [List.filterMap_nil, List.append_nil]; exact h'

theorem lose (_hs : Same same) {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps)
    {p : Pkt V} (hp : p ∈ ps) {ev : Ev V} (hev : p.missed = some ev) :
    KeyOk same (e.step same ev).1 r (after same e (ps.erase p) ev) := by
  unfold after
  cases p with
  | view v => simp [Pkt.missed] at hev
  | read n =>
    simp only [Pkt.missed, Option.some.injEq] at hev; subst hev
    exact readFailed_ok h hp rfl rfl
  | answer n v =>
    simp only [Pkt.missed, Option.some.injEq] at hev; subst hev
    exact readFailed_ok h hp rfl rfl
  | failed n =>
    simp only [Pkt.missed, Option.some.injEq] at hev; subst hev
    exact readFailed_ok h hp rfl rfl
  | write n v =>
    simp only [Pkt.missed, Option.some.injEq] at hev; subst hev
    exact lost_ok h hp rfl rfl
  | acked n =>
    simp only [Pkt.missed, Option.some.injEq] at hev; subst hev
    exact lost_ok h hp rfl rfl
  | refused n =>
    simp only [Pkt.missed, Option.some.injEq] at hev; subst hev
    exact lost_ok h hp rfl rfl

theorem drop {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {v : V} :
    KeyOk same e r (ps.erase (.view v)) := by
  exact erase_stale h (by simp [Pkt.cur, Pkt.seq?])

/-- The current write's phase: `writing v`, the server's value the confirmed one. -/
theorem write_phase {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {n : Nat}
    {v : V} (hp : Pkt.write n v ∈ ps) :
    n = e.seq ∧ e.phase = .writing v ∧ r = e.server ∧ e.written = true := by
  have hn : n = e.seq := by simpa [Pkt.seq?] using h.writes _ hp rfl
  subst hn
  have hs := single h hp (by simp [Pkt.cur, Pkt.seq?])
  have hph := h.phase; rw [hs] at hph
  unfold PhaseOk at hph
  split at hph
  next => simp at hph
  next => obtain ⟨⟨p, hp', hr⟩, -⟩ := hph; simp at hp'; subst hp'; simp [Readish] at hr
  next w hw =>
    obtain ⟨h1 | h1 | h1, h2⟩ := hph
    · simp at h1; obtain ⟨rfl, h3⟩ := h1; exact ⟨rfl, hw, h3, h2⟩
    · simp at h1
    · simp at h1
  next => obtain ⟨⟨p, hp', hr⟩, -⟩ := hph; simp at hp'; subst hp'; simp [Readish] at hr
  next => simp at hph

theorem swapWrite {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {n : Nat}
    {v : V} (hp : Pkt.write n v ∈ ps) {q : Pkt V} {r' : V}
    (hq : (q = .acked n ∧ r' = v) ∨ (q = .refused n ∧ r' = r)) :
    KeyOk same e r' (ps.erase (.write n v) ++ [q]) := by
  obtain ⟨rfl, hph, hr, hw⟩ := write_phase h hp
  have hr' := rest_erase h hp (by simp [Pkt.cur, Pkt.seq?])
  have hqs : q.seq? = some e.seq := by rcases hq with ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> rfl
  have hf : (ps.erase (Pkt.write e.seq v) ++ [q]).filter (Pkt.cur e.seq) = [q] := by
    rw [List.filter_append, hr'.noCur]; simp [Pkt.cur, hqs]
  refine ⟨fun x hx m hm => ?_, fun x hx hxw => ?_, fun hw' => (by rw [hw] at hw'; cases hw'), ?_⟩
  · rcases List.mem_append.1 hx with hx | hx
    · exact hr'.le x hx m hm
    · simp only [List.mem_singleton] at hx; subst hx; rw [hqs] at hm; cases hm; omega
  · rcases List.mem_append.1 hx with hx | hx
    · rw [hr'.noWrite x hx] at hxw; cases hxw
    · simp only [List.mem_singleton] at hx; subst hx; exact hqs
  · rw [hf]; unfold PhaseOk; rw [hph]
    refine ⟨?_, hw⟩
    rcases hq with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact .inr (.inl ⟨rfl, rfl⟩)
    · exact .inr (.inr ⟨rfl, hr⟩)

theorem serveWrite {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {n : Nat} {v : V}
    (hp : Pkt.write n v ∈ ps) : KeyOk same e v (ps.erase (.write n v) ++ [.acked n]) :=
  swapWrite h hp (.inl ⟨rfl, rfl⟩)

theorem swapRead {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {n : Nat}
    (hp : Pkt.read n ∈ ps) {q : Pkt V} (hq : q = .answer n r ∨ q = .failed n) :
    KeyOk same e r (ps.erase (.read n) ++ [q]) := by
  have hqs : q.seq? = some n := by rcases hq with rfl | rfl <;> rfl
  have hqw : q.isWrite = false := by rcases hq with rfl | rfl <;> rfl
  have hqv : ∀ v, q ≠ .view v := by intro v hv; rcases hq with rfl | rfl <;> cases hv
  by_cases hc : (Pkt.read n : Pkt V).cur e.seq = true
  · have hs := single h hp hc
    have hn : n = e.seq := by simpa [Pkt.cur, Pkt.seq?] using hc
    subst hn
    have hr := rest_erase h hp hc
    have hf : (ps.erase (Pkt.read e.seq) ++ [q]).filter (Pkt.cur e.seq) =
        [q] := by
      rw [List.filter_append, hr.noCur]; simp [Pkt.cur, hqs]
    refine ⟨fun q hq m hm => ?_, fun q hq hw => ?_, fun hw => ?_, ?_⟩
    · rcases List.mem_append.1 hq with hq | hq
      · exact hr.le q hq m hm
      · simp only [List.mem_singleton] at hq; subst hq; rw [hqs] at hm; cases hm; omega
    · rcases List.mem_append.1 hq with hq | hq
      · rw [hr.noWrite q hq] at hw; cases hw
      · simp only [List.mem_singleton] at hq; subst hq; rw [hqw] at hw; cases hw
    · have := h.unwritten hw
      have hph := h.phase; rw [hs] at hph; unfold PhaseOk at hph; rw [this.1] at hph
      simp at hph
    · rw [hf]
      have hph := h.phase; rw [hs] at hph
      unfold PhaseOk at hph ⊢
      split at hph
      next => simp at hph
      next => obtain ⟨-, h1, h2, h3⟩ := hph; exact ⟨⟨_, rfl, by rcases hq with rfl | rfl <;> simp [Readish]⟩, h1, h2, h3⟩
      next => obtain ⟨h | h | h, -⟩ := hph <;> simp at h
      next => exact ⟨⟨_, rfl, by rcases hq with rfl | rfl <;> simp [Readish]⟩, hph.2⟩
      next => simp at hph
  · have hc' : (Pkt.read n : Pkt V).cur e.seq = false := by simpa using hc
    have h1 := erase_stale h hc'
    have hm := h.le _ hp n rfl
    have hne : n ≠ e.seq := by intro he; subst he; simp [Pkt.cur, Pkt.seq?] at hc'
    refine ⟨fun q hq m hm' => ?_, fun q hq hw => ?_, fun hw => ?_, ?_⟩
    · rcases List.mem_append.1 hq with hq | hq
      · exact h1.le q hq m hm'
      · simp only [List.mem_singleton] at hq; subst hq; rw [hqs] at hm'; cases hm'; omega
    · rcases List.mem_append.1 hq with hq | hq
      · exact h1.writes q hq hw
      · simp only [List.mem_singleton] at hq; subst hq; rw [hqw] at hw; cases hw
    · refine ⟨(h1.unwritten hw).1, fun v hv => ?_⟩
      rcases List.mem_append.1 hv with hv | hv
      · exact (h1.unwritten hw).2 v hv
      · simp only [List.mem_singleton] at hv; exact absurd hv.symm (hqv v)
    · rw [List.filter_append]
      have : [q].filter (Pkt.cur e.seq) = [] := by simp [Pkt.cur, hqs, hne]
      rw [this, List.append_nil]; exact h1.phase


theorem serveRead {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {n : Nat}
    (hp : Pkt.read n ∈ ps) : KeyOk same e r (ps.erase (.read n) ++ [.answer n r]) :=
  swapRead h hp (.inl rfl)

theorem refuseWrite {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {n : Nat} {v : V}
    (hp : Pkt.write n v ∈ ps) : KeyOk same e r (ps.erase (.write n v) ++ [.refused n]) :=
  swapWrite h hp (.inr ⟨rfl, rfl⟩)

theorem refuseRead {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) {n : Nat}
    (hp : Pkt.read n ∈ ps) : KeyOk same e r (ps.erase (.read n) ++ [.failed n]) :=
  swapRead h hp (.inr rfl)

/-- **A settled key shows the server's value.** -/
theorem converges {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps)
    (hi : e.phase.isIdle = true) : same e.want r = true := by
  have hp := h.phase
  cases hph : e.phase <;> simp only [hph, Phase.isIdle, Bool.false_eq_true] at hi
  simp only [PhaseOk, hph] at hp
  obtain ⟨-, h1, h2⟩ := hp
  rw [← h1]; exact h2

/-- **At most one write in flight.** -/
theorem oneWrite {e : Entry V} {r : V} {ps : List (Pkt V)} (h : KeyOk same e r ps) :
    ps.countP Pkt.isWrite ≤ 1 := by
  have h1 : ps.countP Pkt.isWrite ≤ ps.countP (Pkt.cur e.seq) :=
    List.countP_mono_left fun q hq hw => isWrite_cur h hq hw
  rcases PhaseOk.small h.phase with h2 | ⟨x, h2⟩ <;> have h3 := congrArg List.length h2 <;>
    rw [← List.countP_eq_length_filter] at h3 <;>
    simp only [List.length_nil, List.length_singleton] at h3 <;> omega

end KeyOk

/-! ## Every key -/

namespace World
variable {K V : Type} [Ord K] [Std.TransOrd K] [Std.LawfulEqOrd K] [DecidableEq K] [DecidableEq V]

theorem at_append (a b : List (K × Pkt V)) (k : K) : «at» (a ++ b) k = «at» a k ++ «at» b k :=
  List.filterMap_append

theorem at_single (j : K) (p : Pkt V) (k : K) : «at» [(j, p)] k = if j = k then [p] else [] := by
  by_cases h : j = k <;> simp [«at», h]

theorem at_erase (net : List (K × Pkt V)) (j : K) (p : Pkt V) (k : K) :
    «at» (net.erase (j, p)) k = if j = k then («at» net k).erase p else «at» net k := by
  induction net with
  | nil => simp only [List.erase_nil, «at», List.filterMap_nil]; split <;> rfl
  | cons q net ih =>
    obtain ⟨a, b⟩ := q
    by_cases hq : (a, b) = (j, p)
    · simp only [Prod.mk.injEq] at hq; obtain ⟨rfl, rfl⟩ := hq
      simp only [List.erase_cons_head, «at», List.filterMap_cons]
      by_cases ha : a = k
      · simp only [ha, ↓reduceIte, List.erase_cons_head]
      · simp only [ha, ↓reduceIte]
    · rw [List.erase_cons_tail (by simpa using hq)]
      simp only [«at», List.filterMap_cons] at ih ⊢
      rw [ih]
      by_cases ha : a = k <;> by_cases hj : j = k <;> simp only [ha, hj, ↓reduceIte]
      subst ha; subst hj
      have : b ≠ p := fun h => hq (by rw [h])
      rw [List.erase_cons_tail (by simpa using this)]

theorem mem_at {net : List (K × Pkt V)} {j : K} {p : Pkt V} (h : (j, p) ∈ net) : p ∈ «at» net j := by
  simp only [«at», List.mem_filterMap]
  exact ⟨(j, p), h, by simp only [↓reduceIte]⟩

theorem at_out (os : List (Act V)) (j k : K) :
    «at» ((os.map (Act.out j)).filterMap pktOf) k =
      if j = k then os.filterMap Pkt.ofAct else [] := by
  induction os with
  | nil => simp only [List.map_nil, List.filterMap_nil, «at»]; split <;> rfl
  | cons a os ih =>
    simp only [List.map_cons] at ih ⊢
    cases a <;> simp only [Act.out, pktOf, List.filterMap_cons, Pkt.ofAct] <;>
      first | exact ih | (rw [← List.singleton_append, at_append, at_single, ih]; split <;> rfl)

theorem count_writeOf (os : List (Out K V)) (k : K) :
    (os.filterMap writeOf).count k = Table.writesFor k os := by
  induction os with
  | nil => rfl
  | cons o os ih =>
    simp only [List.filterMap_cons, Table.writesFor, List.countP_cons] at ih ⊢
    cases o <;> simp only [writeOf, ih, List.count_cons, beq_iff_eq] <;>
      first | rfl | (split <;> simp_all)

theorem reg_feed (w : World K V) (i : Input K V) (k : K) : (w.feed i).reg k = w.reg k := rfl

theorem get_feed (w : World K V) (i : Input K V) (k : K) :
    (w.feed i).table.get k =
      if i.key = k then ((w.table.get i.key).step w.table.same i.ev).1 else w.table.get k :=
  Table.get_feed w.table i k

theorem at_feed (w : World K V) (i : Input K V) (k : K) :
    «at» (w.feed i).net k =
      if i.key = k then KeyOk.after w.table.same (w.table.get k) («at» w.net k) i.ev
      else «at» w.net k := by
  simp only [feed, at_append, Table.feed_out, at_out]
  by_cases h : i.key = k
  · subst h; simp only [↓reduceIte, KeyOk.after]
  · simp only [h, ↓reduceIte, List.append_nil]

/-- The table hears `i` in a world whose other keys are fine and whose key `i.key` is fine after
it: then every key is. Budget: `s` more sets of `i.key` (1 for a set). -/
theorem ok_feed (w : World K V) (i : Input K V) (hs : Same w.table.same)
    (hk : ∀ k, i.key ≠ k → KeyOk w.table.same (w.table.get k) (w.reg k) («at» w.net k))
    (hi : KeyOk w.table.same ((w.table.get i.key).step w.table.same i.ev).1 (w.reg i.key)
      (KeyOk.after w.table.same (w.table.get i.key) («at» w.net i.key) i.ev))
    (sets : List K) (hsets : ∀ k, sets.count k = w.sets.count k + Table.setsFor k [i])
    (hb : ∀ k, Entry.Budget w.table.same (w.table.get k) (w.sets.count k) (w.writes.count k)) :
    Ok { w.feed i with sets } := by
  refine ⟨hs, fun k => ?_, fun k => ?_⟩
  · show KeyOk w.table.same ((w.feed i).table.get k) ((w.feed i).reg k) («at» (w.feed i).net k)
    rw [get_feed, at_feed, reg_feed]
    by_cases h : i.key = k
    · subst h; simp only [↓reduceIte]; exact hi
    · simp only [h, ↓reduceIte]; exact hk k h
  · have := Table.budget_feed w.table hs (fun k => w.sets.count k) (fun k => w.writes.count k) hb i k
    show Entry.Budget w.table.same ((w.feed i).table.get k) (sets.count k)
      ((w.writes ++ (w.table.feed i).2.filterMap writeOf).count k)
    rw [hsets, List.count_append, count_writeOf]
    exact this

end World

namespace World.Ok
variable {K V : Type} [Ord K] [Std.TransOrd K] [Std.LawfulEqOrd K] [DecidableEq K] [DecidableEq V]

theorem start (dflt : V) (same : V → V → Bool) (hs : Same same) : (World.start dflt same : World K V).Ok := by
  have hg : ∀ k, (World.start dflt same : World K V).table.get k = Entry.fresh dflt := fun k => by
    simp only [World.start, Table.empty, Table.get, Std.TreeMap.getElem?_emptyc, Option.getD_none]
  refine ⟨hs, fun k => ?_, fun k => ?_⟩
  · rw [hg]
    refine ⟨by simp [World.at, World.start], by simp [World.at, World.start],
      fun _ => ⟨rfl, by simp [World.at, World.start]⟩, ?_⟩
    simp only [PhaseOk, Entry.fresh]
    refine ⟨by simp [World.at, World.start], ?_, hs.refl _⟩
    simp [World.reg, World.start, Table.empty]
  · rw [hg]
    exact ⟨Nat.zero_le _, fun x hx => by simp [Entry.fresh, Phase.pending] at hx⟩

theorem sets_single (w : World K V) (j : K) (f : V → V) (k : K) :
    (w.sets ++ [j]).count k = w.sets.count k + Table.setsFor k [Input.set j f] := by
  simp only [List.count_append, List.count_singleton, Table.setsFor, List.countP_cons,
    List.countP_nil, beq_iff_eq]
  by_cases h : j = k <;> simp [h]

theorem sets_other (w : World K V) (i : Input K V) (hi : ∀ j f, i ≠ .set j f) (k : K) :
    w.sets.count k = w.sets.count k + Table.setsFor k [i] := by
  cases i <;> simp_all [Table.setsFor]

theorem press {w : World K V} (h : w.Ok) (k : K) (f : V → V) : (w.press k f).Ok :=
  World.ok_feed w (.set k f) h.same (fun j _ => h.key j) (KeyOk.press h.same (h.key k) f)
    _ (sets_single w k f) h.budget

theorem retry {w : World K V} (h : w.Ok) (k : K) : (w.retry k).Ok := by
  have := World.ok_feed w (.retry k) h.same (fun j _ => h.key j) (KeyOk.retry h.same (h.key k))
    w.sets (sets_other w _ (by intro j f h; cases h)) h.budget
  exact this

theorem reg_insert (m : Std.TreeMap K V compare) (k j : K) (v d : V) :
    (m.insert k v)[j]?.getD d = if k = j then v else m[j]?.getD d := by
  simp only [Std.TreeMap.getElem?_insert]
  by_cases h : k = j
  · subst h; simp only [Std.ReflCmp.compare_self, ↓reduceIte, Option.getD_some]
  · have : compare k j ≠ .eq := fun h' => h (Std.LawfulEqCmp.eq_of_compare h')
    simp only [this, ↓reduceIte, h]

/-- A step that changes only the server and the network, at key `k`. -/
theorem local_ {w w' : World K V} (h : w.Ok) (ht : w'.table = w.table) (hs : w'.sets = w.sets)
    (hw : w'.writes = w.writes) (k : K)
    (hk : KeyOk w.table.same (w.table.get k) (w'.reg k) (World.at w'.net k))
    (ho : ∀ j, k ≠ j → w'.reg j = w.reg j ∧ World.at w'.net j = World.at w.net j) : w'.Ok := by
  refine ⟨ht ▸ h.same, fun j => ?_, fun j => ht ▸ hs ▸ hw ▸ h.budget j⟩
  rw [ht]
  by_cases hj : k = j
  · subst hj; exact hk
  · rw [(ho j hj).1, (ho j hj).2]; exact h.key j

theorem look {w : World K V} (h : w.Ok) (k : K) : (w.look k).Ok := by
  refine local_ h rfl rfl rfl k ?_ (fun j hj => ⟨rfl, ?_⟩)
  · show KeyOk _ _ (w.reg k) (World.at (w.net ++ [(k, .view (w.reg k))]) k)
    rw [World.at_append, World.at_single]; simp only [↓reduceIte]
    exact KeyOk.look (h.key k)
  · show World.at (w.net ++ [(k, .view (w.reg k))]) j = _
    rw [World.at_append, World.at_single]; simp only [hj, ↓reduceIte, List.append_nil]

theorem serve {w : World K V} (h : w.Ok) (k : K) (p : Pkt V) : (w.serve k p).Ok := by
  unfold World.serve
  split
  · rename_i hm
    have hp := World.mem_at hm
    split
    · rename_i n v
      refine local_ h rfl rfl rfl k ?_ (fun j hj => ⟨?_, ?_⟩)
      · simp only [World.at_append, World.at_erase, World.at_single, ↓reduceIte, World.reg,
          reg_insert]
        exact KeyOk.serveWrite (h.key k) hp
      · simp only [World.reg, reg_insert, hj, ↓reduceIte]
      · simp only [World.at_append, World.at_erase, World.at_single, hj, ↓reduceIte,
          List.append_nil]
    · rename_i n
      refine local_ h rfl rfl rfl k ?_ (fun j hj => ⟨rfl, ?_⟩)
      · simp only [World.at_append, World.at_erase, World.at_single, ↓reduceIte]
        exact KeyOk.serveRead (h.key k) hp
      · simp only [World.at_append, World.at_erase, World.at_single, hj, ↓reduceIte,
          List.append_nil]
    · exact h
  · exact h

theorem refuse {w : World K V} (h : w.Ok) (k : K) (p : Pkt V) : (w.refuse k p).Ok := by
  unfold World.refuse
  split
  · rename_i hm
    have hp := World.mem_at hm
    split
    · refine local_ h rfl rfl rfl k ?_ (fun j hj => ⟨rfl, ?_⟩)
      · simp only [World.at_append, World.at_erase, World.at_single, ↓reduceIte]
        exact KeyOk.refuseWrite (h.key k) hp
      · simp only [World.at_append, World.at_erase, World.at_single, hj, ↓reduceIte,
          List.append_nil]
    · refine local_ h rfl rfl rfl k ?_ (fun j hj => ⟨rfl, ?_⟩)
      · simp only [World.at_append, World.at_erase, World.at_single, ↓reduceIte]
        exact KeyOk.refuseRead (h.key k) hp
      · simp only [World.at_append, World.at_erase, World.at_single, hj, ↓reduceIte,
          List.append_nil]
    · exact h
  · exact h

theorem heard_key (k : K) (p : Pkt V) (i : Input K V) (hi : World.heard k p = some i) :
    i.key = k ∧ p.heard = some i.ev := by
  cases p <;> simp only [World.heard, Option.some.injEq, reduceCtorEq] at hi <;> subst hi <;>
    exact ⟨rfl, rfl⟩

theorem missed_key (k : K) (p : Pkt V) (i : Input K V) (hi : World.missed k p = some i) :
    i.key = k ∧ p.missed = some i.ev := by
  cases p <;> simp only [World.missed, Option.some.injEq, reduceCtorEq] at hi <;> subst hi <;>
    exact ⟨rfl, rfl⟩

theorem heard_set (k : K) (p : Pkt V) (i : Input K V) (hi : World.heard k p = some i) :
    ∀ j f, i ≠ .set j f := by
  intro j f he; subst he; cases p <;> simp [World.heard] at hi

theorem missed_set (k : K) (p : Pkt V) (i : Input K V) (hi : World.missed k p = some i) :
    ∀ j f, i ≠ .set j f := by
  intro j f he; subst he; cases p <;> simp [World.missed] at hi

/-- The packet `(k, p)` leaves the network and the table hears `i` about `k`. -/
theorem erase_feed {w : World K V} (h : w.Ok) (k : K) (p : Pkt V) (i : Input K V) (hk : i.key = k)
    (hset : ∀ j f, i ≠ .set j f)
    (hi : KeyOk w.table.same ((w.table.get k).step w.table.same i.ev).1 (w.reg k)
      (KeyOk.after w.table.same (w.table.get k) ((World.at w.net k).erase p) i.ev)) :
    ({ w with net := w.net.erase (k, p) } : World K V).feed i |>.Ok := by
  have := World.ok_feed ({ w with net := w.net.erase (k, p) } : World K V) i h.same
    (fun j hj => by
      show KeyOk _ _ (w.reg j) (World.at (w.net.erase (k, p)) j)
      rw [World.at_erase]; simp only [hk ▸ hj, ↓reduceIte]; exact h.key j)
    (by
      subst hk
      show KeyOk _ _ (w.reg i.key) (KeyOk.after _ _ (World.at (w.net.erase (i.key, p)) i.key) _)
      rw [World.at_erase]; simp only [↓reduceIte]; exact hi)
    w.sets (sets_other _ i hset) h.budget
  exact this

theorem deliver {w : World K V} (h : w.Ok) (k : K) (p : Pkt V) : (w.deliver k p).Ok := by
  unfold World.deliver
  split
  · rename_i hm
    split
    · rename_i i hi
      obtain ⟨hk, hev⟩ := heard_key k p i hi
      exact erase_feed h k p i hk (heard_set k p i hi)
        (KeyOk.deliver h.same (h.key k) (World.mem_at hm) hev)
    · exact h
  · exact h

theorem lose {w : World K V} (h : w.Ok) (k : K) (p : Pkt V) : (w.lose k p).Ok := by
  unfold World.lose
  split
  · rename_i hm
    split
    · rename_i i hi
      obtain ⟨hk, hev⟩ := missed_key k p i hi
      exact erase_feed h k p i hk (missed_set k p i hi)
        (KeyOk.lose h.same (h.key k) (World.mem_at hm) hev)
    · rename_i hi
      have hv : ∃ v, p = .view v := by cases p <;> simp_all [World.missed]
      obtain ⟨v, rfl⟩ := hv
      refine local_ h rfl rfl rfl k ?_ (fun j hj => ⟨rfl, ?_⟩)
      · show KeyOk _ _ (w.reg k) (World.at (w.net.erase (k, .view v)) k)
        rw [World.at_erase]; simp only [↓reduceIte]; exact KeyOk.drop (h.key k)
      · show World.at (w.net.erase (k, .view v)) j = _
        rw [World.at_erase]; simp only [hj, ↓reduceIte]
  · exact h

/-- **Every step keeps `Ok`.** -/
theorem step {w w' : World K V} (h : w.Ok) (hs : World.Step w w') : w'.Ok := by
  cases hs with
  | press k f => exact h.press k f
  | serve k p => exact h.serve k p
  | refuse k p => exact h.refuse k p
  | deliver k p => exact h.deliver k p
  | lose k p => exact h.lose k p
  | retry k => exact h.retry k
  | look k => exact h.look k

/-- **Convergence.** In a world reached by any steps, in any order, every settled key (nothing in
flight, nothing in doubt) shows what the server holds. -/
theorem converges {w : World K V} (h : w.Ok) (k : K) (hk : w.table.settled k = true) :
    w.table.same (w.table.shown k) (w.reg k) = true :=
  KeyOk.converges (h.key k) hk

/-- **One write in flight per key**: at most one write about `k` in the network, before or after
the server handled it. -/
theorem oneWrite {w : World K V} (h : w.Ok) (k : K) :
    (World.at w.net k).countP Pkt.isWrite ≤ 1 :=
  KeyOk.oneWrite (h.key k)

/-- **Never more writes than sets.** -/
theorem writes_le_sets {w : World K V} (h : w.Ok) (k : K) : w.writes.count k ≤ w.sets.count k :=
  (h.budget k).1

/-- **Counts.** For a boolean key with the view's count `o + [v]` (others `o`, the person's own
`v`), a settled key shows `o + [what the server holds]`; exactly the server's count when no one
else acted since the view. -/
theorem count {w : World (K) Bool} (h : w.Ok) (hsame : w.table.same = fun a b => a == b) (k : K)
    (hk : w.table.settled k = true) (o : Nat) (v : Bool) :
    Optimistic.count (o + ind v) v (w.table.shown k) = o + ind (w.reg k) := by
  have := h.converges k hk
  rw [hsame] at this
  simp only [beq_iff_eq] at this
  rw [this]; exact count_view o v _

end World.Ok

/-- **Any run** of steps from the start keeps `Ok`. -/
theorem World.Ok.reach {K V : Type} [Ord K] [Std.TransOrd K] [Std.LawfulEqOrd K] [DecidableEq K]
    [DecidableEq V] {w w' : World K V} (h : w.Ok) (hr : World.Reach w w') :
    w'.Ok := by
  induction hr with
  | refl => exact h
  | tail _ hs ih => exact ih.step hs

namespace World
variable {K V : Type} [Ord K] [DecidableEq K] [DecidableEq V]

/-! `same` and `dflt` never change. -/

theorem press_same (w : World K V) (k : K) (f : V → V) : (w.press k f).table.same = w.table.same := rfl
theorem retry_same (w : World K V) (k : K) : (w.retry k).table.same = w.table.same := rfl
theorem look_same (w : World K V) (k : K) : (w.look k).table.same = w.table.same := rfl
theorem serve_same (w : World K V) (k : K) (p : Pkt V) : (w.serve k p).table.same = w.table.same := by
  unfold serve; split
  · split <;> rfl
  · rfl
theorem refuse_same (w : World K V) (k : K) (p : Pkt V) : (w.refuse k p).table.same = w.table.same := by
  unfold refuse; split
  · split <;> rfl
  · rfl
theorem deliver_same (w : World K V) (k : K) (p : Pkt V) : (w.deliver k p).table.same = w.table.same := by
  unfold deliver; split
  · split <;> rfl
  · rfl
theorem lose_same (w : World K V) (k : K) (p : Pkt V) : (w.lose k p).table.same = w.table.same := by
  unfold lose; split
  · split <;> rfl
  · rfl

end World

end Cairn.Optimistic
