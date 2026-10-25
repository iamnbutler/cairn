---
title: The evidence ladder
nav: The evidence ladder
eyebrow: Reference
lede: How sure we are of each claim: proved, fuzzed, tested, seen or assumed, computed by the build and shown on the claim pages.
---

Every claim carries a list of evidence, one entry for each kind it can have. Each entry is a
**pass**, a **fail**, or a **gap**: evidence the claim could have and doesn't, because the input
wasn't run or never reached it. None of it is typed by hand; the build computes all of it.

## The ladder

Strongest first:

| Kind | Where it comes from | Passes when |
|---|---|---|
| **proved** | the axiom audit of every theorem | every theorem the claim names (each handler's `sound`; a flow's `live` and `reaches`; an invariant's `init`, `step` and `reachable`) exists and uses only `propext`, `Classical.choice` and `Quot.sound` |
| **fuzzed** | `cairn fuzz` | the claim's checks held in every random sequence that exercised it; for an assumption, every trusted-base check naming it held |
| **tested** | `cairn conformance` | the running app matched the Lean model at every step that exercised it |
| **seen** | the app capture (none runs today: it went with the example apps, [#137](https://github.com/iamnbutler/cairn/issues/137)) | a move's control is in a captured frame; a flow's whole witness was replayed, each step on the control it names |
| **assumed** | the claim is an `assume` | always: it is stated, never proved |

Proved and fuzzed are about the Lean model; tested and seen are about the app. A proof says more,
but only conformance reaches through the host, so a claim keeps every chip, not just its best one.
A move is fully covered when it is proved, fuzzed, tested and seen.

Which kinds each claim can have:

| Claim | proved | fuzzed | tested | seen | assumed |
|---|---|---|---|---|---|
| move | ✓ | ✓ | ✓ | ✓ | |
| flow | ✓ | | ✓ | ✓ | |
| invariant | ✓ | ✓ | ✓ | | |
| assume | | ✓ | | | ✓ |
| place | | | | ✓ | |

Flows aren't fuzzed, because their paths are proved live. Invariants aren't seen, because a
screenshot can't show that something holds in every state.

## How a claim reads

To make a list of claims scannable, each claim also reads as one word:

| Reads as | When |
|---|---|
| retired | it is retired: it shows its reason and nothing else |
| broken | any of its evidence failed |
| assumed | it is an assumption, even when fuzzed |
| proved, fuzzed, tested or seen | the strongest kind it passes |
| untested | it is live and has no evidence at all |

A **fail** is a named theorem missing from the audit or using another axiom; a fuzz failure, with
the command that replays it; a conformance failure; or a flow whose step names a control the
captured app doesn't show. A claim missing from `claims.lock`, or whose statement changed without
being accepted, is reported with it.

## Claim pages

Every package's [claim pages](/docs/evidence/) show the part of the ladder its published claims
export holds: proved (with each theorem's axioms) and assumed, plus a flow's witness and retired
and moved ids. Fuzzed, tested and seen come from builds that run the app, and are listed as not
shown yet until CI publishes them. `cairn doc` shows the whole ladder locally, from `build/`.

## What isn't evidence yet

- **Seen** is the Lean model's own frames, rendered by the real renderer, not the running app's
  window. Conformance is what covers the host.
- Some rarer text operations (word movement, input-method composition, cut and copy) aren't
  replayed by the capture yet, so a flow that uses one is only partly seen.
- **Presence and pressability** theorems aren't linked to their claims yet, so they don't count
  toward a claim's proved. The fuzzer checks both for every move.
- **Kernel replay** covers the whole build, not each theorem.
