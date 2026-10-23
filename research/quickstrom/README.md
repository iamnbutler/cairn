---
title: "Quickstrom: Property-based Acceptance Testing with LTL Specifications (and its TodoMVC spec; successor Bombadil)"
url: https://arxiv.org/abs/2203.11532
author: Liam O'Connor, Oskar Wickström
date: 2022-03-22 (arXiv); PLDI 2022, doi:10.1145/3519939.3523728. Spec at quickstrom/quickstrom 5eafc22. Bombadil announced 2026-01-28.
relevance: 5
---

# Quickstrom / Specstrom / QuickLTL

## What it is

A browser testing tool that takes a temporal-logic spec of a web UI (which actions exist, what
state to read from the DOM, which properties must hold), drives a real browser with random
actions, and reports a trace that violates the spec. The paper's evaluation is a formal TodoMVC
spec run against 43 implementations. Archived here:

- [raw/quickstrom-pldi2022-arxiv-2203.11532.tex](raw/quickstrom-pldi2022-arxiv-2203.11532.tex):
  the paper's LaTeX source from arXiv (CC BY-SA 4.0).
- [raw/case-studies_todomvc.strom](raw/case-studies_todomvc.strom) with
  [raw/case-studies_todomvc_elements.strom](raw/case-studies_todomvc_elements.strom) (state
  queries) and [raw/case-studies_todomvc_operators.strom](raw/case-studies_todomvc_operators.strom)
  (`becomes`, `+=`): the spec, 304 + 60 + 26 lines (BSD-3-Clause, [raw/LICENSE](raw/LICENSE)).
- [raw/todomvc.md](raw/todomvc.md): the authors' per-implementation results notes.

Lineage: WebCheck (2020, PureScript specs; blog post "The TodoMVC Showdown", 2020-07-02) →
Quickstrom/Specstrom (PLDI 2022) → **Bombadil** (Antithesis, 2026, TypeScript specs, Rust
runner, MIT, github.com/antithesishq/bombadil, now "Property-based testing for web and terminal
UIs").

## Key findings (quoted, with locations in the .tex)

**QuickLTL** (§2, L341–563). Tests only ever see finite, partial traces, so plain LTL gives the
wrong answers. They extend RV-LTL's four values (definitely/presumably true/false) with a
*required next* and a length subscript on every temporal operator: "to check □ₙφ, Quickstrom
must check at least n states for φ before concluding that the formula is presumptively true".
Evaluation is formula progression: unroll against the current state, simplify, and if a
required-next remains, take another action.

**Specs are not models** (§6.4, L1039–1046): model-based PBT "require[s] that the model capture
the essential complexity of the application … Quickstrom specifications can be more abstract …
free to leave out details". The TodoMVC spec is a state machine over *observations*:
`initial ∧ □(focusNewTodo ∨ enterNewTodoText ∨ addNew ∨ changeFilter ∨ setSameFilter ∨ toggleAll ∨
checkOne ∨ uncheckOne ∨ delete ∨ enterEditMode ∨ inEditMode) ∧ □⟨invariants⟩` (Fig. "Sketch of our
TodoMVC specification", L790–818). Editing is a nested machine entered by `enterEditMode` and
left via `Release` on commit/abort; "we also 'remember' the original value of an item … so that
we can specify that the text returns to its original value if an edit is aborted" (L834).

**The informal spec is ambiguous** (§5.1, L759–770): "our formalisation efforts show the
official specification is rife with ambiguity and under-specification." Two examples: what
filter change does to the rest of the UI ("Our formal specification makes the reasonable
assumption that no other part of the interface (such as pending input) should be modified"),
and the filter after deleting all items (left undefined; de-facto "unchanged").

**Results** (§5.2, L887–933, Tables "Summary of Results" and "Problems found"): 43
implementations tested, **20 failed** ("almost half"; the abstract says "more than a third";
Wickström's 2026 post says "more than half"; the table says 20/43 = 47%). The 14 problems:

| # | Problem | Impls |
|---|---|---|
| 1 | Items have no checkboxes | 1 |
| 2 | There are no filter controls | 2 |
| 3 | A `<strong>` element is missing | 1 |
| 4 | Blank items can be added | 1 |
| 5 | Edit input is not focused after double-click | 1 |
| 6 | Incorrectly pluralizes the to-do count text | 1 |
| 7 | Any pending input is cleared on filter change or removal of last item | 4 |
| 8 | A new item is created from pending input after non-create actions | 2 |
| 9 | "Toggle all" does not untoggle all items when certain filters are enabled | 1 |
| 10 | The "Toggle all" button disappears when the current filter contains no items | 1 |
| 11 | Committing an empty to-do item in edit mode does not fully delete it; it can later be restored with "Toggle all" | 1 |
| 12 | Editing an item hides other items | 1 |
| 13 | Adding an item changes the filter to "All" | 2 |
| 14 | Adding an item first shows an empty state (dubious) | 1 |

"problems often manifest when the user does something unexpected after entering (but not
committing) some input text … the interaction between filters and the 'Toggle all' button is
another common source of bugs" (L926–928). Even the three reference implementations (vanillajs,
vanilla-es6, jquery) failed. Elm failed (row 4, blank items).

**Cost of random search** (§5.3, Fig. "False negative rate", L935–1000): false-negative rate
100% at subscript 1, 64.5% at 10, 30.5% at 50, 21.4% at 100 (default, ~42 s per passing
implementation), 8.1% at 500. "the more involved faults such as Problem 11 are only found
infrequently, resulting in flaky tests."

**What the spec leaves out**, read from `case-studies_todomvc.strom`:

- Every action except typing is guarded `when not isInEditMode`, so behaviour of other controls
  during an edit is unspecified.
- Delete is `click!(.destroy)`; hover is never exercised and the spec does not check that delete
  is hidden without hover.
- "We have not yet formalized the persistence aspect" (L840). No reload action.
- `typePendingText!` types only `" ", "a", "b", backspace`; edit text only `"c", backspace`. So
  trimming and Unicode are barely explored, and the counter is never checked above small N.
- Initial state requires `selectedFilter == null`, i.e. filters hidden with no items; after
  `addNew` from `null`, any filter may appear ("we don't know what it was").
- Abort is `[keyPress!(escape), click!(body)]`: an Escape *followed by a blur*. That is exactly
  the sequence that breaks implementations which commit on blur after Escape (TodoMVC #1801).

**Counter-evidence / limits** (§6, L1062–1071): only single-trace properties; hyperproperties
(information flow) are out of reach. Bombadil post: "Both the original hacky PureScript DSL and
the bespoke language Specstrom were huge obstacles to adoption." Third-party coverage of Bombadil
notes actions are still chosen blindly at random (Wickström: no smart exploration yet).

## For Cairn

- **Adopt (I):** the bug table as a regression list. Each row is a claim M1 must make and
  prove: rows 7–8 → pending-text frame conditions (T9, T10 in
  [../todomvc/README.md](../todomvc/README.md)); 9–11 → toggle-all over all items and
  "deleted means gone"; 12–13 → editing and adding leave the filter and other items alone. In
  Cairn these are theorems about `update`, which removes the false-negative curve entirely for
  the model; conformance (J) still has to show the host matches the model.
- **Adopt (A):** Quickstrom's split of a move into *guard* (`when …`), *action* and
  *postcondition with frame conditions* (`unchanged([...])`) maps one-to-one onto a `move`
  claim's `enabled` / `update` / `post`. Make "unchanged" first-class in the claim language so
  frame conditions are cheap to state, since they are where the bugs are.
- **Adopt (A, I):** nested machines. Edit mode as a sub-machine with a remembered original
  value is the right shape for `flow` claims and for the edit `Field` (D).
- **Study (J):** QuickLTL's progression semantics is a ready-made monitor for conformance: the
  Lean model gives exact next states, but properties about the host (e.g. "the frame after the
  event shows X within k frames") need presumptive answers over finite traces. Consider the
  length-subscripted operators for timing properties of the host.
- **Study (J):** their action alphabet is tiny (4 keystrokes). Our generator should draw text
  from a richer distribution: leading/trailing whitespace (including non-ASCII spaces Lean's
  `String.trim` may or may not strip), empty, long, combining marks. Decide what "trim" means
  (ASCII whitespace vs Unicode White_Space) and claim it.
- **Avoid:** acceptance testing as the *only* evidence. Quickstrom must read state back from
  the DOM through selectors (`elements.strom`), and markup drift excluded implementations (gwt).
  Cairn's accessibility mirror with `^N` identifiers is the stable selector Quickstrom lacked.
- **Counter-evidence to keep in mind:** Quickstrom's "specs not models" argument says complete
  models grow as complex as the system. For TodoMVC the Lean app *is* the model; that argument
  bites when Cairn reaches apps with external state.
