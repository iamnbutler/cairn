---
title: Verified GUIs — Agda state-dependent GUIs (Adelsberger, Setzer, Walkingshaw) and PVS medical-device UIs (Masci et al.)
url: https://eric.walkingshaw.net/files/pubs/2018/ppdp18-declarative-guis.pdf
author: Stephan Adelsberger, Anton Setzer, Eric Walkingshaw; Paolo Masci, Yi Zhang, Paul Jones, Paul Curzon, Harold Thimbleby
date: PPDP 2018 (doi:10.1145/3236950.3236962); FASE 2014 (doi:10.1007/978-3-642-54804-8_14)
relevance: 4
---

# Verified GUIs in a proof assistant

## What it is

The two closest precedents for "proofs about the GUI app itself", from opposite directions:

1. **Declarative GUIs: Simple, Consistent, and Verified** (PPDP 2018; author's version read in
   full). An Agda library where the GUI's controller type depends on a declarative GUI
   specification, compiled to an SDL/Rasterific Haskell back-end. A case study with the Medical
   University of Vienna (anticoagulant prescribing) proves reachability properties of the
   *executable* GUI. Earlier version on wxWidgets: "Developing GUI Applications in a Verified
   Setting" (SETTA 2018).
2. **Formal Verification of Medical Device User Interfaces Using PVS** (FASE 2014) and the
   PVSio-web toolkit (github.com/pvsioweb/pvsio-web): translate an existing device's UI code into
   PVS, verify human-factors properties, then generate tests to confirm issues on the real
   device.

No formally verified GUI or trusted display path on seL4 turned up (search 2026-10-23); seL4
work stops at the kernel and roots of trust.

## Key findings (quoted)

**Agda (PPDP 2018).**

- Motivation: "Model checking has been used to prove the absence of certain kinds of bugs, but
  model checking works on an abstract model of the GUI application, which might be inconsistent
  with its implementation" (abstract).
- Mechanism: "the type of a GUI's controller depends on a specification of the GUI itself,
  statically enforcing consistency between them. Arbitrary properties can be defined and proved
  in terms of user interactions and state transitions" (abstract).
- Reachability is an inductive relation over *well-typed command sequences*: "Cmds essentially
  defines a sequence of commands parameterized by a State type that statically ensures that each
  input corresponds to the preceding state" and `data _-gui->_ (s : State) : State → Set` with
  constructors `refl-gui->` and `step (c : Cmd s) → guiNext s c -gui-> s' → s -gui-> s'` (§4.2), alongside an `-eventually->` relation for "every path reaches" (§4.2, used by theoremWarfarin).
- Example theorems are domain properties: `theoremWarfarin` ("given a complete set of [inputs]
  … is prescribed") and `theoremNoLowDosisWeight>60` , proved by case distinction (§5.4).
- Trade-off with a real toolkit (§6): "The version presented here is much simpler (since
  wxWidgets is an inherently imperative toolkit with concurrency, interfacing to it from Agda
  leads to significant complexity) … However, wxWidgets integrates better with the host
  operating system".
- Not covered: layout, hit testing, text editing, conformance of the back-end. The Haskell
  back-end and its drawing are trusted.

**PVS (FASE 2014).** "it first translates the software implementation of user interface into an
equivalent formal specification, from which a behavioral model is constructed using theorem
proving; human factors properties are then verified against the behavioral model; lastly, a
comprehensive set of test inputs are produced by exploring the behavioral model, which can be
used to challenge the real interface implementation and to ensure that the issues detected in
the behavior model do apply to the implementation … The analysis detected several interaction
design issues in the device" (abstract).

## For Cairn

- **Adopt (A, I):** the Agda reachability relation is exactly what a Cairn `flow` claim's
  "checked witness path" needs: a list of moves, each enabled in the state before it, ending in a
  state satisfying the flow's goal. Define it once in `Cairn.Claims` as an inductive `Reach`
  (with `decide`-able checking for concrete witnesses) rather than per app.
- **Adopt (C, G):** their lesson about back-ends. Their proofs got simpler when they replaced an
  imperative toolkit (wxWidgets) with a declarative renderer they controlled. Cairn already chose
  the second path (Lean frames, thin Metal host); hold that line when it is tempting to delegate
  a control to AppKit (e.g. using `NSTextField` for the edit field would put T25–T31 of
  [../todomvc/README.md](../todomvc/README.md) outside the proofs).
- **Adopt (J):** PVSio-web's last step, "test inputs … produced by exploring the behavioral model
  … to challenge the real interface implementation", is Cairn's conformance driver. Their framing
  is useful for `docs/trusted.md`: a proof about the model plus model-derived tests on the device
  is two kinds of evidence, and the map's evidence column should say which a claim has.
- **Go further than both (B, C):** neither proves anything about what is on screen: whether the
  control for a command is visible, unoccluded and hit-testable. Cairn's *presence* and
  *pressable* theorems are, as far as this search found, new for GUIs in a proof assistant. Say
  so carefully (we did not search exhaustively) and keep the statements small and checkable.
- **Counter-evidence:** both projects' properties are *domain* properties (dosing rules, number
  entry). TodoMVC's domain is trivial; its bugs are in interaction details (pending text, focus,
  Escape vs blur). Our claims need to reach that level of detail to be worth proving.
