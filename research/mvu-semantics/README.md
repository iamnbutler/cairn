---
title: The Elm Architecture and formal semantics of MVU/React-style UIs (λMVU, Essence of React, React-tRace, Willow, Smalite)
url: https://guide.elm-lang.org/architecture/
author: Evan Czaplicki (Elm guide); Simon Fowler (λMVU); Madsen, Lhoták, Tip; Lee, Ahn, Yi; Wunder, Das, Gaboardi; Pesin, Picard, Allignol
date: Elm guide fetched 2026-10-23; ECOOP 2020 (λMVU, React); 2025 (React-tRace, Smalite); 2026 (Willow)
relevance: 4
---

# Model-View-Update and its formal treatments

## What it is

Cairn's `App S` (`init`, `view : S → UI → Node`, `update : S → Action → S × List Effect`) is the
Elm Architecture with effects as data. This note collects what has been *proved* about that
shape, and what has not.

Sources read: the Elm guide's architecture chapter; Fowler, "Model-View-Update-Communicate:
Session Types meet the Elm Architecture", ECOOP 2020, arXiv 1910.11108 (extended version, full
text); Madsen, Lhoták, Tip, "A Semantics for the Essence of React", ECOOP 2020, LIPIcs 166
12:1–12:26 (full text, CC BY); abstracts of React-tRace (arXiv 2507.05234), Willow (arXiv
2607.27074) and Smalite (arXiv 2508.13610).

## Key findings (quoted)

- **Elm guide:** "Model — the state of your application; View — a way to turn your state into
  HTML; Update — a way to update your state based on messages". It "seems to emerge naturally in
  Elm. Rather than someone inventing it, early Elm programmers kept discovering the same basic
  patterns".
- **Counter-evidence: the architecture is not a spec.** Elm's TodoMVC failed Quickstrom with
  "Blank items can be added" ([../quickstrom/README.md](../quickstrom/README.md), Table
  "Problems found", row 4). Pure `update` makes behaviour testable and provable; it does not
  make it correct.
- **λMVU (Fowler 2020)** is a core calculus of MVU and proves *type soundness of the runtime*,
  not properties of apps: "Theorem 2 (Preservation). If ⊢ C and C −→ C′, then ⊢ C′" and
  "Theorem 4 (Event Progress) … either there are no events to process and the system is idle,
  or the system can reduce" (§2.3). History: Elm's "core formal semantics, was
  published at PLDI 2013 … Elm gained a user community, and a standard architectural pattern
  known as The Elm Architecture grew organically to such a point that Elm abandoned FRP
  altogether" (§1).
- **Model transitions** (λMVU §3.3): with one sum-typed model "we need to include cases in the
  update function which cannot arise … we require multiple model types, and a way to transition
  between them … model transitions eliminate the redundant code paths arising due to illegal
  states."
- **React semantics (Madsen et al. 2020)**: small-step semantics of components, reconciliation
  and lifecycle hooks; termination of mounting/unmounting/reconciliation via a ranking function:
  "we define the notion of a well-behaved component and prove that well-behavedness is
  preserved by these operations" (abstract). Paper proofs, no mechanization.
- **React-tRace (2025)**: a semantics for Hooks validated by "empirically comparing our
  React-tRace-definitional interpreter against a test suite" (abstract).
- **Willow (2026)**: timing bugs in render-based UIs, "stale reads, transient inconsistencies,
  order-dependent behavior, and unintended feedback cycles", tracked by a type-and-effect system
  with a "next" modality; "prove preservation of the effect system" (abstract).
- **Smalite (2025)**, from the aviation HMI community (ENAC): "Although these domain-specific
  languages are now widely used to implement safety-critical GUIs, little work has been invested
  in their formalization and verification … a stepping stone to produce a formally verified
  compiler for UIDLs" (abstract).

### What none of these do

None proves a *particular app* meets a behavioural spec, none treats layout or hit testing, and
none connects the semantics to what reaches the screen. They are about the framework's runtime
(soundness, termination, timing). The closest thing to "app-level proofs over executable GUI
code" is the Agda work in [../verified-gui/README.md](../verified-gui/README.md).

## For Cairn

- **Adopt (C):** state the runtime's own soundness as theorems, λMVU-style, since Cairn's runtime
  is Lean: every `Event` the runtime accepts yields either no `Action` or exactly one `Action`
  naming a control present in the current frame (the "event progress"/"no stray message"
  analogue). This is the theorem that makes "there is no way to react to input except through a
  move" (docs/plan.md, Principles) a fact rather than a convention.
- **Adopt (I, A):** model transitions as the answer to "unreachable cases in update". For
  TodoMVC, edit mode is the candidate: make `editing : Option EditState` part of the state and
  have edit moves only *exist* (be enabled) when it is `some`, so presence and `update` agree by
  construction. Lean's dependent types let us go further than λMVU (a move's argument type can
  depend on the state), but keep the claim-level view flat: one move id per action.
- **Study (C):** Willow's timing hazards (stale reads, transient inconsistency, feedback loops)
  are what Cairn's three-thread host could reintroduce *outside* Lean: the render thread drawing
  an older frame than the accessibility mirror, or the main thread delivering an event against a
  stale hit-test. Record the ordering assumptions in `docs/trusted.md` and have J check that the
  frame the event was hit-tested against is the frame the user saw.
- **Avoid (A, C):** virtual-DOM-style reconciliation as the source of identity. React's
  reconciliation decides "same component" by position and keys; Cairn's identity is the claim id
  plus key in `ControlRef`, chosen by the app, never inferred by diffing. See
  [../imgui-identity/README.md](../imgui-identity/README.md).
