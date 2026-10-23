---
title: XState / statecharts model-based testing (xstate/graph, createTestModel, @xstate/test)
url: https://stately.ai/docs/graph
author: Stately (David Khourshid et al.)
date: docs fetched 2026-10-23 (site labels "XState v6 alpha"); @xstate/test README at tag xstate@4.38.3
relevance: 3
---

# XState model-based testing

## What it is

XState models app logic as statecharts. Its graph utilities treat a machine as a directed graph
and generate event paths; `createTestModel` replays each path against the real app, with a user
callback per event (how to perform it) and per state (what to assert). `@xstate/test` was the
original package; the docs now say "The graph utilities are now included in the main `xstate`
package. Import from `xstate/graph` instead of the deprecated `@xstate/graph` package."

## Key findings (quoted from stately.ai/docs/graph)

- Purpose: "Model-based testing - automatically generate test cases that cover all reachable
  states and transitions … Validation - verify all states are reachable and all transitions are
  exercised".
- Two traversals: "Shortest paths use Dijkstra's algorithm to find the minimum number of
  transitions to reach each state … Simple paths use depth-first search to find all possible
  non-cyclic paths … Simple paths provide complete transition coverage".
- **State explosion with data** is pushed to the user: "When machines have dynamic context, the
  state space can become infinite. Use `stopWhen` or `limit` to bound the traversal"; events
  with payloads must be enumerated by hand (`events: [{ type: 'INC', value: 1 }, …]` or a
  function of the state); state identity for de-duplication is `serializeState`, by default
  "JSON strings of their value and context".
- Test shape: `path.test({ events: { TOGGLE: async () => { await page.click('#toggle-button') }
  }, states: { inactive: async (state) => { await expect(page.locator('#status')).toHaveText(
  'Inactive') } } })`. The mapping from model events to UI actions, and from model states to
  UI assertions, is hand-written and untyped against the app.
- Observability caveat (stately.ai/docs/testing): "states that are only entered and left via
  eventless (`always`) transitions in the same step are not observable".
- Original pitch (@xstate/test README, v4): "Create a visual model, tell it how to interact with
  your app, and execute the model to **test your app automatically**."

### Counter-evidence

Quickstrom's authors argue against complete models for testing: model-based PBT requires "that
the model capture the essential complexity of the application under test", which for complex
apps "tends to grow as complex as the system itself" (Quickstrom PLDI 2022 §6.4; see
[../quickstrom/README.md](../quickstrom/README.md)). XState sidesteps this by modelling only
finite control states and leaving data to `context` plus bounds, which then limits coverage.

## For Cairn

- **Adopt (J):** both traversals. Shortest paths give one witness per reachable abstract state
  (cheap, deterministic, good for `flow` witnesses and for the map's screenshots); simple paths
  give transition coverage. For the 1,000-sequence conformance run, seed with all shortest paths
  to each abstract TodoMVC state (filter × {empty, all active, mixed, all completed} × editing ×
  pending text empty/non-empty), then add random extensions.
- **Adopt (J):** `serializeState` as an explicit *abstraction function*. In Cairn this is a Lean
  function `abstract : S → AbsState` with a finite enumeration (a `List AbsState` plus a completeness lemma; no Mathlib `Fintype`); prove that every move's
  enabledness depends only on `abstract s` where that is true, so the abstract graph's coverage
  means something.
- **Avoid (J, A):** the untyped, hand-written event and state mappings. In Cairn the move id *is*
  the event, the debug socket performs it by hit-testing the control `^N#k`, and the assertion is
  "accessibility tree and frame equal the model's", so there is nothing to keep in sync by hand.
  This is the main advantage of claims-as-ids over XState's string event names.
- **Study (J):** XState's observability caveat applies to Cairn's host: a state that exists only
  between two Lean updates within one host frame is never painted. Conformance should compare
  per *frame presented*, and the model should say which intermediate states are allowed to be
  skipped (cf. Quickstrom row 14, "Adding an item first shows an empty state").
