# TodoMVC: requirements to claims

Every requirement in [research/todomvc](../../../research/todomvc/README.md) (T1–T50), and the
claim or code that covers it. Claim ids are durable (`claims.lock`); T-numbers are research
labels only. Each claim's `does` names the T-numbers it covers, so the map shows them too.

Files: `../Todo.lean` (claims, machine, ABI), `Model.lean` (state and moves), `View.lean` (view),
`Tests.lean` (runtime checks with mono metrics), `Proofs.lean` (presence, pressable, the
invariants on screen), `host/Sources/CairnTodo` (host and self test).

## What is proved

- Every move's `post`, for every state where it is enabled (the `machine`'s sound goals).
- `reachable_invariants`, `invariants_on_screen`: in every reachable state, and in every state
  the running app reaches whatever events arrive, the counter equals the active todos, ids are
  distinct, and the rows are `visible s` (the filter applied to the todos), in order.
- `presence`, `presence_in_frame`, `presence_on_screen`: for every move `mv` of the machine and
  key `k`, the control `⟨mv.id, k⟩` is in the view, in the frame's accessibility tree and on
  screen exactly when `mv.enabled s k` holds and either `mv` is a row move (^204–^207) or
  `k = 0`. Unkeyed moves draw their one control with key 0. The row cases come from
  `mem_flatMap_keyed`, which works for any list that draws one group of controls per item, all
  keyed by the item's id.
- `view_fitsIn`, `view_pressable`, `enabled_pressable`: in **any** window at least `minWidth`
  (389) wide and `height s` tall, with **any** text metrics, hit testing at the centre of every
  control (and so of every enabled move's control) returns that control. This needs the window
  to be that size: there is no scrolling (not in M1), so with more todos than fit, the rows below
  the window are off screen and the theorem says nothing about them. The host's window is
  560×720, which fits 11 todos under one filter.

Not proved: that a click at a control's centre *performs* the move. `Cairn.Runtime.click_presses`
needs the control to still be under the pointer after the pointer down. That fails exactly in
the dropped-click case below.

| T | Covered by | How |
|---|---|---|
| T1 | view; ^203, ^208–^211 `enabled` | with no todos the view has only the header and info line; toggle all, filters and Clear completed are disabled |
| T2 | ^203, ^208–^210 `enabled := !s.todos.isEmpty` | shown with any todo, whatever the filter |
| T3 | ^202, `View.header`, `newPlaceholder` | heading "todos", placeholder "What needs to be done?" |
| T4 | `View.info` | static text, not a claim (nothing to do) |
| T5 | `app` (`initFocus := ^202`) | `Tests`: focus at start; self test |
| T6 | ^202 `on submit`, `post := Added` | appended at the end, trimmed, active; flow ^216 |
| T7 | ^202 `Added` | `s'.newField.text = []` |
| T8 | ^202 `Added`; flow ^217 | blank: `s' = s` (decision below) |
| T9 | ^202 has no `blur` handler; every other move's `post` fixes `todos` exactly | `dispatch_unhandled`: a blur of ^202 does nothing |
| T10 | `post` of ^203–^211 | each states `s'.newField = s.newField` (filters: `s' = { s with filter }`) |
| T11 | ^202 `Added` | `s'.filter = s.filter`; flow ^224 |
| T12 | flow ^224 | created, not listed under Completed |
| T13 | runtime | one `update` per action, then one view; no intermediate frame |
| T14 | ^203 | present iff there are todos, in every filter |
| T15 | `View.header` | `checked := allDone s`, over all todos |
| T16 | ^203 `post` | `s.todos.map (setDone (!allDone s))`, hidden todos included; flow ^223 |
| T17 | T15 + ^211 | after Clear completed no todo is completed |
| T18 | ^204, ^205, ^206 | one row per listed todo |
| T19 | ^204 `post` | `s.todos.map (flip k)`; completed titles drawn grey with a check |
| T20 | ^205 `on doublePress`; ^214 | double-click on the title |
| T21 | ^206; `View.hot` | the × is drawn while the pointer is over the row's controls (decision T49) |
| T22 | ^206 `post` | `s.todos.filter (·.id ≠ k)`, nothing else |
| T23 | posts | `map` and `filter` keep order; `Added` appends |
| T24 | ^212 | ids strictly increase, below `nextId`, never reused |
| T25 | ^205 `Started`; view; ^204/^206 `enabled` | the edit row has only the field, focused |
| T26 | `State.editing : Option Editing` | at most one, by type |
| T27 | ^205 `Started` | todos, count, filter and pending text unchanged |
| T28 | ^207 `on submit`, `Committed` | flow ^218 |
| T29 | ^207 `on blur`, `Committed` | flow ^219 (decision below) |
| T30 | ^207 `Committed` | blank deletes; ids are never reused (^212), so nothing brings it back |
| T31 | ^207 `on cancel` | title unchanged; the field's removal drops focus without a blur (docs/runtime.md); flow ^220 |
| T32 | — | nothing is persisted yet (T47) |
| T33 | runtime | decision below |
| T34 | ^212 | `s.left = active s.todos`, over all todos; the view shows `s.left` |
| T35 | `View.itemsWord` | "item" iff 1; `Tests` |
| T36 | `View.footer` | the number is a separate bold run |
| T37 | ^211 `enabled := anyDone s` | |
| T38 | ^211 `post` | `s.todos.filter (!·.completed)`; flow ^222 |
| T39 | ^208, ^209, ^210 | All, Active, Completed, in that order |
| T40 | ^226 | the rows are `visible s`, in order, in every reachable state |
| T41 | `View.filterBox` | `selected := s.filter = f`, a border on the current one |
| T42 | ^226; flow ^221 | rows are recomputed from the todos every frame |
| T43 | ^208–^210 `post` | `s' = { s with filter := f }` |
| T44 | — | not yet: persistence is not implemented |
| T45 | ^206, ^207 `post` | delete keeps the filter |
| T46 | ^215 (retired) | web only |
| T47 | — | not yet: persistence is not implemented |
| T48 | decision | what persistence will store |
| T49 | ^206 | always in the accessibility tree and the Tab order (decision below) |
| T50 | ^207 `on submit`/`on cancel` emit `focus ^202` | decision below |

Decisions (also in `docs/plan.md`): T8 blank Enter changes nothing, whitespace stays; T29 blur is
a click elsewhere or Tab, not the window losing key; T33 a click elsewhere saves first, then acts;
T48 persist todos and filter only; T49 delete always present, glyph on hover or focus; T50 focus
returns to the new-todo field after Enter or Escape in an edit.

Known gaps: persistence (T44, T47); editing has no keyboard or VoiceOver path (the title is not
focusable, and double-click is pointer-only). A click that ends an edit can be dropped: the blur
saves first (T33), and if that save deletes the todo, the row or button that was clicked can move
or vanish (the last todo goes, so toggle all goes too) before the release, as in a browser. Tests
show it (`Tests.lean`). `make fuzz APP=Todo` and `make conformance APP=Todo` meet it (fuzz seed
260, ^208; conformance walk-1-823 step 7, ^203: both edit the last todo to blank, then click a
control that goes with it) and label it T33 instead of failing: the fuzzer counts it as
`droppedT33`, the conformance run under `known` (docs/fuzz.md, docs/conformance.md). It is
exactly where `Runtime.click_presses`'s hypothesis fails, so code, model and proofs agree.
