---
title: How much to trust a claim
nav: How much to trust a claim
eyebrow: Reference
lede: What each kind of evidence rules out, what it still takes on trust, and a bug that Basics' tests miss and its proof can't.
---

A claim's evidence says *proved*, *fuzzed*, *tested*, *seen* or *assumed*. This page says what
each of those words buys you: what it rules out, and what you still have to trust when you rely
on it. [The evidence ladder](/docs/reference/evidence/) says how the build computes them.

| Evidence | Rules out | Still trusts |
|---|---|---|
| **proved** | a counterexample anywhere: every state, every key, every input | that the statement says what you mean; Lean's kernel and compiler; the trusted base |
| **fuzzed** | a counterexample in the sequences the fuzzer ran | that the random sequences reach the case that matters |
| **tested** | the running app disagreeing with the model, on the sequences run | the conformance harness; nothing about sequences it didn't run |
| **seen** | a control that is never drawn, a flow that can't be clicked through | the capture, which renders the model's frames, not the running window |
| **assumed** | nothing | whoever wrote it, and the checks that gather evidence for it |

A claim keeps every kind it has, not just the strongest, because they cover different things. A
proof is about the Lean model; only conformance runs the real app, and only the capture puts it
on screen.

## Proved

**What is checked.** Every theorem the claim names (a move's `sound`, a flow's `live` and
`reaches`, an invariant's `init` and `step`) exists and was accepted by Lean's kernel. `make
check` audits each one's axioms: only `propext`, `Classical.choice` and `Quot.sound` are
allowed, so a `sorry` or a new `axiom` anywhere underneath shows up. A lint rejects the escape
hatches that would skip the kernel (`native_decide`, `implemented_by`, `debug.skipKernelTC`), and
every declaration is replayed through the kernel once more.

**What it rules out.** Every case, not a sample of them. A move's `post` holds in every state
where the move is enabled, for every key and every text edit; an invariant holds in every state
the app can reach. No test suite can say that.

**What it still trusts.**

- **The statement.** A proof shows that the formal statement holds, not that it says what you
  meant. `post s' := True` is easy to prove and promises nothing. Nothing checks that the `does`
  and `sees` prose says what `post` says; that is review's job. The
  [API reference](/docs/api/claims.html) prints each claim's formal statement next to its words
  so a reader can compare them, and the ledger warns when a statement changes, so a weakened
  promise shows in review.
- **Lean.** Its kernel, which checks the proofs, and its compiler, which builds the code that
  actually runs. The proofs are about the definitions; the compiled code is trusted to behave
  like them. Banning `implemented_by` keeps the two the same code.
- **Everything below the bytes.** The proofs end at the frame Lean sends: the host, AppKit, Core
  Text, Metal and the GPU are [the trusted base](/docs/internals/trusted-base/), each piece an
  assumption with its own checks.

## Fuzzed

**What is checked.** `make fuzz` runs random sequences of moves against the Lean model and, after
every step, checks each claim it can: a move's `post`, its control's presence and pressability,
every invariant. For an assumption, the trusted-base fuzzer runs the real host code against
Lean's proved code or another oracle. A failure prints the command that replays it.

**What it rules out.** A counterexample in the sequences it ran: 200 by default, and as many as
you ask for. That is far more than a person writes by hand, and the fuzzer tries the odd orders
people don't.

**What it still trusts.** That a bug is reachable in a short random walk. A case that needs a
rare, long or precise setup can hide from it. For a move or an invariant, fuzzing is a cheap
second opinion on what the proof already covers; for an assumption, which has no proof, it is
the evidence.

## Tested

**What is checked.** `make conformance` drives the real app (its Swift host, its compiled Lean)
through its debug socket and compares every frame with what the Lean model says it should be.

**What it rules out.** The running app and the model disagreeing, on the sequences it ran. It is
the only evidence that reaches through the host.

**What it still trusts.** The harness: events are injected at the view, not through the window
server; keys are built as a US keyboard would produce them; no real input method runs; frames
are compared through two JSON printers, one per language. And it says nothing about sequences it
didn't run.

## Seen

**What is checked.** The capture renders the app's frames with the real renderer and replays
each flow's witness, clicking each step's control where it was laid out. A move is seen when its
control is in a captured frame; a flow, when its whole witness replays.

**What it rules out.** A control that is never drawn, and a flow that can't be clicked through.
It is also the evidence a person can look at.

**What it still trusts.** That the model's frames are what the app shows: the capture renders
Lean's frames, not the running window. Conformance is what ties the two together. Some rarer text
operations (word movement, input-method composition) aren't replayed yet, so a flow that uses
one is only partly seen.

## Assumed

An `assume` claim states something the proofs rely on and can't prove, most often about the
host: that the clock never goes backwards, that the host reports clicks where they happen. It
always reads as assumed, even when fuzzed, so it never passes for a proof.

**What it rules out.** Nothing by itself. Its evidence is whatever checks it: Cairn's own
assumptions each name a fuzz check (`check "name"`) and are listed with their results on
[the trusted base](/docs/internals/trusted-base/) page.

**What it still trusts.** Whoever wrote it. That is the next question.

## Who checks an `assume`?

Cairn's checks are built to catch an honest author's mistakes, and they do that well. They are
not a defence against an author who means to mislead you, and it is worth being exact about why.

An honest author is kept honest by the build:

- An assumption's formal statement is a definition, never an axiom: a theorem that relies on it
  takes it as a hypothesis, so the reliance is written in the theorem's own statement.
- Every assumption is a claim with an id, kind `assume`, in the package's ledger and its API
  reference. You can list them all.
- A claim's statement can't change quietly: the ledger hashes it, warns on a change, and needs
  `ledger update --accept`, which shows in review. Ids are never reused.

A hostile author has more room:

- An `assume` can state something false. Nothing proves it; only a check the author chose to
  write gathers evidence for it.
- A `post` can be weak, and `does` and `sees` can promise more than the formal statement does.
  The proof is real; it just proves less than the prose says.
- An app's own Swift code, such as a Metal shader it draws with, is outside the proofs.
- Cairn's lint, axiom audit and kernel replay run in Cairn's repository. An app in its own
  repository has no `cairn check` yet, and the package registry records each version's ledger
  but doesn't rebuild it or re-run its proofs.

So read a package you don't trust for its statements, not its green ticks. List its `assume`
claims and decide whether you believe each one. Read each claim's formal statement beside its
prose. Build it yourself and run the checks, so the evidence is your kernel's and not the
publisher's report.

## A bug the tests miss

Basics, the [example app](/docs/examples/basics/) with a list of items, keeps a count of the items
not done in its state instead of counting them in the view. Invariant ^105 says the count is
always right:

<bongo:include src="lean/Examples/Basics.lean#basics-inv" />

`delete` keeps the count: it takes one off only when the item it removes wasn't done.

<bongo:include src="lean/Examples/Basics.lean#basics-delete" />

Here is the same function with one plausible slip. It takes one off whatever the item was:

<bongo:include src="lean/Examples/Basics/Mutant.lean#mutant-delete" />

**The tests pass.** This is Basics' own test of deleting: add two items, check the first, delete
the second.

<bongo:include src="lean/Examples/Basics/Tests.lean#basics-tests-delete" />

The deleted item wasn't done, so the buggy `delete` takes one off, exactly as it should. Deleting
the only item, done or not, gives the right answer too, because `Nat` subtraction stops at zero:
`0 - 1` is `0`. With the bug planted in Basics itself, every one of its tests and all three of
its flows still build and pass. The same steps, on `deleteBuggy`:

<bongo:include src="lean/Examples/Basics/Mutant.lean#mutant-tests" />

**The proof doesn't.** ^105's `step` needs a proof that `delete` keeps the invariant, and the one
that works for `delete` stops at the count. This is that proof, written for `deleteBuggy`, with
the message Lean gives. `#guard_msgs` makes the build check that the attempt fails with exactly
this message:

<bongo:include src="lean/Examples/Basics/Mutant.lean#mutant-attempt" />

Read the constraints as a description of the bug. `c` is the number of items not done after the
delete and `d` is the count the state now keeps; `c - d ≥ 1` says the count is too low. `b` is
what deleting the item should have taken off, and the constraints allow `b = 0`: an item that was
done. So the failing case is deleting a done item while an item that isn't done remains. Lean
didn't need a test to find it. It made it concrete, and it can be proved:

<bongo:include src="lean/Examples/Basics/Mutant.lean#mutant-counterexample" />

**What the other evidence would have said.** With the bug planted, `make fuzz APP=Basics` with
its defaults (200 random sequences from seed 0) failed ^105 in 22 of them, the first at step 49
of seed 9. Fuzzing would very likely have caught this one. Conformance and the capture would not
have: the app would match its own buggy model, frame for frame, and the screenshots would look
fine. The proof is the only evidence that guarantees the case is covered, rather than likely to
have come up. And because Basics' invariant is proved, `make check` fails before this change can
merge.

## Checking a claim yourself

1. **Read the claim.** Its entry in the [API reference](/docs/api/claims.html) shows its `does`
   and `sees`, its formal statement, its proofs and its evidence. Check that the statement says
   what the prose does.
2. **Look for assumptions.** Find the package's `assume` claims among its claims, and read the
   trusted base. Every proof you rely on takes those as given.
3. **Run the checks.** `make check` builds every proof, audits its axioms, replays the kernel and
   runs the ledger; `make fuzz` and `make conformance` gather the rest. Evidence you built is
   evidence you don't have to take on anyone's word.
