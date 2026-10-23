# TodoMVC: requirements to claims

Every requirement in [research/todomvc](../../../research/todomvc/README.md) (T1–T50), and the
claim or code that covers it. Claim ids are durable (`claims.lock`); T-numbers are research
labels only. Each claim's `does` names the T-numbers it covers, so the map shows them too.

Files: `../Todo.lean` (claims, machine, ABI), `Model.lean` (state and moves), `View.lean` (view),
`Tests.lean` (runtime checks with mono metrics), `host/Sources/CairnTodo` (host and self test).

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
| T40 | ^213 | the rows are `visible s`, in order, in every reachable state |
| T41 | `View.filterBox` | `selected := s.filter = f`, a border on the current one |
| T42 | ^213; flow ^221 | rows are recomputed from the todos every frame |
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
focusable, and double-click is pointer-only); a click whose target moves because the save
deleted a row above it is dropped, as in a browser.
