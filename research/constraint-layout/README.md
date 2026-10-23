---
title: Constraint and one-pass UI layout — Cassowary, Auto Layout, ORC, Flutter's box protocol
url: https://constraints.cs.washington.edu/solvers/cassowary-tochi.pdf
author: Greg Badros, Alan Borning, Peter Stuckey (Cassowary); Apple (Auto Layout docs); Yue Jiang et al. (ORC); Flutter team
date: Cassowary ACM TOCHI 8(4) 2001; ORC Layout arXiv 1912.07827 (Jiang, Du, Lutteroth, Stuerzlinger; CHI 2019); Apple and Flutter docs fetched 2026-10-23
relevance: 3
---

# Constraint layout and what "correct layout" means there

## What it is

The other family of UI layout: declare linear constraints with priorities, let a solver find
positions. Cassowary (incremental dual simplex over constraint hierarchies) underlies Apple's
Auto Layout and many ports (kiwi, Swift `inamiy/Cassowary`). Contrasted here with Flutter's
one-pass box protocol, which is the shape Cairn's layout already has. None of these has a
mechanized correctness proof that I could find (search 2026-10-23); their correctness story is
solver theory plus testing and runtime diagnostics.

## Key findings (quoted)

- **Constraint hierarchies** (Cassowary §1.1): "each constraint has a strength. The required
  strength is special, in that required constraints must be satisfied. The other strengths all
  label non-required constraints. A constraint of a given strength completely dominates any
  constraint with a weaker strength". Unsatisfiable required constraints raise an exception
  ("unsatisfiable constraints", Fig. 8 pseudocode).
- **Floating point drift**, acknowledged in the API: `reset()` "Re-initialize[s] the solver
  from the original constraints, thus getting rid of any accumulated numerical problems. (It is
  not yet clear how often such problems arise, but we provide the method just in case.)"
  (Appendix A.2).
- **Ambiguity is a runtime debugging property in Auto Layout.** `NSView.hasAmbiguousLayout`:
  "A Boolean value indicating whether the constraints impacting the layout of the view
  incompletely specify the location of the view … Accessing this property engages the layout
  engine to determine whether any other frame would also satisfy the constraints … This
  property should be used only for debugging constraint-based layout. Do not access this
  property in the shipping version of your app." (Apple developer documentation, AppKit
  `NSView.hasAmbiguousLayout`).
- **ORC Layout** (arXiv 1912.07827): adds OR-constraints to soft/hard linear systems so one spec
  can switch between grid and flow; "ORC design patterns that enable designers to *safely*
  create flexible layouts that work across different screen sizes" (abstract). Safety is a
  design-pattern discipline, not a proof.
- **Flutter** ("Understanding constraints", docs.flutter.dev/ui/layout/constraints):
  "Constraints go down. Sizes go up. Parent sets position." and "Flutter's layout engine is
  designed to be a one-pass process … A widget can decide its own size only within the
  constraints given to it by its parent … A widget can't know and doesn't decide its own
  position in the screen … If a child wants a different size from its parent and the parent
  doesn't have enough information to align it, then the child's size might be ignored."

## For Cairn

- **Avoid (B):** solver-based layout in anything a theorem mentions. A simplex solve over
  floats has no clean total-function statement; ambiguity and unsatisfiability are runtime
  outcomes Apple tells you not to check in shipping code. Cairn's "deterministic sizes"
  theorem would have to become "the solver returned a solution satisfying all required
  constraints", and even that depends on float pivots.
- **Adopt (B):** Flutter's one-pass protocol as the reference shape, because each of its rules is
  a lemma we can prove about `layout`: the child's size lies within the constraints the parent
  passed (gives "children inside their parent's clip" when combined with positioning), the
  parent alone sets position (gives sibling disjointness for row/column), and the "child's size
  might be ignored" case is exactly where clipping theorems must say what happens.
- **Study (B, A):** strengths as *claims*. If Cairn ever wants preferences (e.g. "the delete
  button prefers 40pt but may shrink"), model them as a lexicographic order on a small finite
  set of candidate layouts chosen by a total function, and claim which preference won, rather
  than embedding an optimizer.
- **Counter-evidence:** constraint layout's selling point is that designers state relations
  ("left-of", "inside") directly; a one-pass layout makes those relations *theorems* someone has
  to prove. For M1's fixed TodoMVC shape that cost is small; for user-authored layouts it may
  not be.
