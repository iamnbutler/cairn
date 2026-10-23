---
title: TodoMVC application specification, test suite and template
url: https://github.com/tastejs/todomvc/blob/master/app-spec.md
author: TodoMVC maintainers (Addy Osmani, Sindre Sorhus, Pascal Hartig, Stephen Sawchuk and contributors)
date: app-spec.md and cypress/e2e/spec.cy.js at tastejs/todomvc ff43b02 (2026-05-02); template and CSS from tastejs/todomvc-app-template and todomvc-app-css master, fetched 2026-10-23
relevance: 5
---

# TodoMVC: the spec M1 has to meet

## What it is

TodoMVC is the same to-do app written in many frameworks. What it should do is defined by three
things, none of them formal:

1. **`app-spec.md`**: about 40 lines of English under "Functionality". Archived as
   [raw/app-spec.md](raw/app-spec.md) (MIT).
2. **The Cypress suite** (`cypress/e2e/spec.cy.js`, 1,037 lines, 27 `it` cases) that the
   maintainers run against every example. It fixes some things the prose leaves open, e.g. that
   new items go to the bottom and that the back button walks back through filters. Archived as
   [raw/todomvc-spec.cy.js](raw/todomvc-spec.cy.js). Known failures per implementation are in
   [raw/todomvc-knownIssues.js](raw/todomvc-knownIssues.js).
3. **The template markup and CSS**, which set the visible text ("What needs to be done?",
   "Mark all as complete", "Clear completed", "Double-click to edit a todo") and some behaviour
   the prose only implies, e.g. delete appears on hover: `.todo-list li:hover .destroy {
   display: block; }` ([raw/todomvc-app-css-index.css](raw/todomvc-app-css-index.css) line 254;
   [raw/template-index.html](raw/template-index.html)).

Gaps in all three are filled in practice by what the reference apps do and by bug reports. The
most careful reading so far is Quickstrom's formal spec; see
[../quickstrom/README.md](../quickstrom/README.md). Where it decides something the prose leaves
open, the requirement below cites it.

## Key findings (quoted)

- No todos: "When there are no todos, `#main` and `#footer` should be hidden." (app-spec.md L84)
- New todo: "The input element should be focused when the page is loaded … Pressing Enter creates
  the todo, appends it to the todo list, and clears the input. Make sure to `.trim()` the input
  and then check that it's not empty before creating a new todo." (L88)
- Mark all: "This checkbox toggles all the todos to the same state as itself. Make sure to clear
  the checked state after the "Clear completed" button is clicked. The "Mark all as complete"
  checkbox should also be updated when single todo items are checked/unchecked. Eg. When all the
  todos are checked it should also get checked." (L92)
- Item: "Clicking the checkbox marks the todo as complete … Double-clicking the `<label>`
  activates editing mode … Hovering over the todo shows the remove button (`.destroy`)" (L98–102)
- Editing: "it will hide the other controls and bring forward an input that contains the todo
  title, which should be focused (`.focus()`). The edit should be saved on both blur and enter
  … Make sure to `.trim()` the input and then check that it's not empty. If it's empty the todo
  should instead be destroyed. If escape is pressed during the edit, the edit state should be
  left and any changes be discarded." (L106)
- Counter: "Displays the number of active todos in a pluralized form … `0 items`, `1 item`,
  `2 items`." (L110)
- Clear completed: "Removes completed todos when clicked. Should be hidden when there are no
  completed todos." (L114)
- Persistence: "use the keys `id`, `title`, `completed` for each item … Editing mode should not
  be persisted." (L118)
- Routing: "`#/` (all - default), `#/active` and `#/completed` … the todo list should be filtered
  on a model level and the `selected` class on the filter links should be toggled. When an item
  is updated while in a filtered state, it should be updated accordingly. E.g. if the filter is
  `Active` and the item is checked, it should be hidden. Make sure the active filter is
  persisted on reload." (L122)
- Cypress pins down order and history: "should append new items to the bottom of the list"
  (spec.cy.js L595) and "should respect the back button" (L981, `cy.go('back')` twice walks
  Completed → Active → All).

### Counter-evidence and known ambiguity

- The spec is silent on what other actions do to **pending text** in the new-todo field. Four
  implementations cleared it on filter change and two committed it as a todo on unrelated
  actions (Quickstrom PLDI 2022, Table "Problems found", rows 7 and 8).
- It is silent on **which filter is selected after the last item is removed**. Quickstrom: "there
  seems to be a commonly understood de-facto specification that the filter should be
  unchanged … but we have not formalised this as it is not officially specified".
- **Escape after emptying the field**: issue
  [#1801](https://github.com/tastejs/todomvc/issues/1801), "if we rename any todo to blank-name
  (""), and then press escape, then instead of ignoring the changes … the todo gets deleted in
  the jQuery version". Escape fires, the field is removed, the removal fires blur, and blur
  commits. Issues [#789](https://github.com/tastejs/todomvc/issues/789) (26 implementations
  did not cancel on Escape) and [#530](https://github.com/tastejs/todomvc/issues/530) ("Maria
  saves on escape") are the same family.
- **Accessibility**: the reference design is mouse-only for edit and delete. Issue
  [#1017](https://github.com/tastejs/todomvc/issues/1017): "they are unusable on non-mobile
  devices without a mouse". `display: none` on `.destroy` also removes it from the
  accessibility tree until hover.
- "Toggle all" acts on **all** todos, not just the visible ones ("toggles all the todos"). Dojo
  got this wrong under filters (Quickstrom row 9).

## The requirements (M1's claims start here)

These are numbered `T1`… for research only; they are **not** claim ids. Workstream I turns each
into one or more claims (`move`, `invariant`, `flow`, `assume`) and records the mapping. Sources:
**S** = app-spec.md line, **C** = Cypress test (spec.cy.js line), **H** = template HTML/CSS,
**Q** = Quickstrom spec (`../quickstrom/raw/case-studies_todomvc.strom`) or its bug table,
**I** = TodoMVC issue, **D** = de-facto, not written anywhere official. *Mac* marks an
adaptation, *Decide* an open choice for workstream I.

### Visibility and structure

- **T1** With zero todos, the main section (toggle-all and list) and the footer (counter,
  filters, clear completed) are not shown. (S84; C551)
- **T2** With one or more todos, the main section and the footer are shown, whatever the filter
  and even when the filtered list is empty. (C632; Q `hasFilters`, `hasToggleAll`; Q row 10)
- **T3** The header shows the heading "todos" and the new-todo field with placeholder "What
  needs to be done?". (H)
- **T4** The info footer says "Double-click to edit a todo". (H)

### New todo

- **T5** At launch, keyboard focus is in the new-todo field. (S88; C533) *Mac:* "page load" is
  window open / app launch.
- **T6** Enter in the new-todo field, when `trim(text) ≠ ""`, creates one todo with
  `title = trim(text)` and `completed = false`, appended at the end of the list. (S88; C561,
  C595, C613)
- **T7** After T6 the new-todo field is empty. (S88; C589)
- **T8** Enter with `trim(text) = ""` creates nothing. (S88; Q `addNew` "Blank todo items cannot
  be created"; Q row 4) *Decide:* whether the whitespace stays in the field; Quickstrom accepts
  "nothing changes".
- **T9** Enter is the only way pending text becomes a todo. Blur, filter change, toggle,
  toggle-all, delete, edit and clear completed never create a todo. (Q `addNew` "Pressing return
  is the only way to create a todo item"; Q row 8, which vanillajs and vanilla-es6 failed)
- **T10** Pending new-todo text is unchanged by every action other than typing in that field
  and T6: filter change, toggle, toggle-all, delete (including the last item), edit, clear
  completed. (Q `changeFilter`, `checkOne`, `delete`, `toggleAll`, `startEditing`, `commitEdit`
  all assert `unchanged(newTodoInput.pendingText)`; Q row 7, four implementations failed)
- **T11** Creating a todo does not change the selected filter. (Q `addNew`; Q row 13)
- **T12** Under the Completed filter a new todo is created but not listed (it is active). (Q
  `addNew` case "Completed"; I [#355](https://github.com/tastejs/todomvc/issues/355))
- **T13** The new list is shown in one step: no intermediate empty state. (Q row 14, "dubious")
  Trivial for an atomic `update`, but conformance should still check it frame by frame.

### Toggle all

- **T14** The toggle-all control ("Mark all as complete") is present whenever there is at least
  one todo, in every filter, including when the filtered list is empty and while no item is
  being edited. (H: it lives in `#main`; Q `hasToggleAll`; Q row 10)
- **T15** Toggle-all reads as checked iff every todo (over all todos, not the visible ones) is
  completed. It updates when single items are toggled, added, deleted or cleared. (S92; C690)
- **T16** Activating toggle-all when some todo is active marks every todo completed; when every
  todo is completed it marks every todo active. Hidden todos are included. (S92; C663, C677;
  Q `toggleAll` cases per filter; Q row 9)
- **T17** After Clear completed, toggle-all reads unchecked (or is absent if no todos remain).
  (S92) Follows from T15 and T35; prove it rather than state it separately.

### An item

- **T18** Each listed todo shows a checkbox, its title, and (see T21) a delete button. (H)
- **T19** Clicking a todo's checkbox flips its `completed`. Completed todos are visibly marked
  (template: struck-through, greyed). (S98; C728, C747)
- **T20** Double-clicking a todo's title enters edit mode for that todo. (S100; C763)
- **T21** The delete button of a todo is shown while the pointer hovers that todo's row. (S102;
  H css L228 `display:none`, L254 `li:hover .destroy {display:block}`)
- **T22** Clicking delete removes that todo and nothing else. (H; Q `delete`: `numItems -= 1`,
  filter unchanged; with one item left, the list becomes empty)
- **T23** Todos keep creation order. Toggling and editing never reorder. (C595; C763 checks
  the edited item stays at index 1)
- **T24** Todo ids are unique and never reused while the app runs. (S118 names an `id` key;
  GOAL.md invariant)

### Editing

- **T25** In edit mode the item's checkbox, title and delete button are hidden and an edit
  field containing the current title is shown and focused. (S106; C803; Q `startEditing`
  `editInput.active`; Q row 5)
- **T26** At most one todo is in edit mode. (Q `numInEditMode == 1`; knownIssues.js: somajs
  "You can get multiple elements into an edit state")
- **T27** Entering edit mode changes nothing else: other items stay listed, and the filter,
  counter and pending new-todo text are unchanged. (Q `startEditing`; Q row 12)
- **T28** Enter in the edit field commits: if `trim(text) ≠ ""` the title becomes `trim(text)`;
  edit mode ends. (S106; C763, C832)
- **T29** Blur of the edit field commits exactly as T28. (S106; C811) *Mac/Decide:* what counts
  as blur: a click elsewhere in the window certainly; Tab; the window resigning key. Decide and
  write it as an `assume` or a move.
- **T30** Committing with `trim(text) = ""` deletes the todo, completely: no later action
  (toggle-all, filter change, clear completed) brings it back. (S106; C849; Q row 11,
  backbone_marionette)
- **T31** Escape in the edit field ends edit mode and leaves the title exactly as before,
  including when the field is empty. Leaving edit mode by Escape must not then commit through
  blur. (S106; C864; I #1801, #789, #530)
- **T32** Edit mode is not persisted. (S118)
- **T33** *Decide:* what other controls do while editing. Quickstrom only generates other
  actions `when not isInEditMode`, so it says nothing. On the web a click elsewhere blurs
  (commit, T29) and then performs its own action. Pick one and claim it.

### Counter

- **T34** The footer shows `N item left` / `N items left` where `N` is the number of active
  todos over all todos, not the filtered list. (S110; C881; Q `correctFilterStates` "All":
  `todoCount == numUnchecked`)
- **T35** "item" iff `N = 1`, otherwise "items" (`0 items`, `1 item`, `2 items`). (S110; Q
  `itemsLeftPluralized`; Q row 6, polymer) `0 items left` is reachable: one or more todos, all
  completed.
- **T36** The number is emphasised (web: wrapped in `<strong>`). (S110; Q row 3) *Mac:* a
  separate bold text run; expose the number in the accessibility value.

### Clear completed

- **T37** "Clear completed" is shown iff at least one todo is completed. (S114; C895, C913; H)
- **T38** Activating it removes every completed todo (over all todos, not the visible ones);
  active todos remain in order. (S114; C900)

### Filters (routing)

- **T39** Three filters, All, Active and Completed, shown in that order. All is the default.
  (S122; H; Q `hasFilters` `availableFilters == ["All","Active","Completed"]`)
- **T40** The listed todos are exactly the todos satisfying the filter, in creation order: All
  every todo, Active `¬completed`, Completed `completed`. (S122 "filtered on a model level";
  C970, C1004, C1011; GOAL.md invariant)
- **T41** Exactly one filter is shown as selected and it is the current one. (S122; C1020)
- **T42** A change to an item takes effect on the filtered list at once, e.g. checking an item
  under Active removes it from the list. (S122; Q `checkOne` "Active" case)
- **T43** Selecting a filter changes only the filter: todos, pending text and the counter are
  unchanged. Selecting the current filter changes nothing. (Q `changeFilter`, `setSameFilter`)
- **T44** The selected filter survives relaunch. (S122 "Make sure the active filter is
  persisted on reload")
- **T45** Removing the last todo leaves the filter unchanged, so the next todo added appears
  under the same filter. (D; Quickstrom paper §5.1, and Q `addNew` case `null` "should enable
  the last used filter") Not official; adopt it, and say it is ours.
- **T46** *Web-only, not adopted on the Mac:* hash routes `#/`, `#/active`, `#/completed` (also
  `#!/`), and the back button walking filter history (S122; C981). Record a retired-at-birth
  note so the omission is explicit, or add a Back command later if a history is wanted.

### Persistence

- **T47** Every change to todos is persisted (`id`, `title`, `completed`), and relaunching
  restores the same todos in the same order with the same completion. (S118; C921) *Mac:* a
  file instead of `localStorage['todos-<framework>']`; GOAL.md allows "persistence beyond a
  file" to be out of scope, so a file is in scope.
- **T48** What is persisted is exactly todos and filter (T44): not edit mode (T32), not pending
  new-todo text (unspecified, *Decide*), not hover or focus.

### Hover, focus and pointer (implied, not stated)

- **T49** Delete is reachable without hover for keyboard and VoiceOver users. Not in the
  TodoMVC spec, and the reference design fails it (I #1017). *Decide:* it conflicts with T21 if
  the accessibility mirror only shows what is drawn. See "For Cairn".
- **T50** Focus: after T6 focus stays in the new-todo field; after leaving edit mode by any route
  focus goes to *Decide* (the web apps lose focus to `body`).

## For Cairn

- **Adopt (I, A):** T1–T50 as the M1 checklist. Every one becomes a claim or is explicitly
  marked web-only/decided. Keep a table in `lean/Examples/Todo/` mapping `T<n>` to claim ids so
  reviewers can audit coverage against this note, and list the *Decide* items in the PR that
  makes the choice.
- **Adopt (I):** state the "unchanged" frame conditions (T10, T27, T43) as theorems about
  `update`. They are where half of the real-world bugs were (Quickstrom rows 7, 8, 12, 13), and
  in a pure Lean `update` they are cheap to prove: each move touches named fields only.
- **Adopt (A, C):** presence depends on hover (T21). `App.view : S → UI → Node` already takes
  the runtime's `UI`, so the presence theorem must be stated relative to `UI` ("delete's
  control is in the frame iff the todo is listed and its row is hovered"), and the pressable
  theorem needs a hover-then-press path, not a single press. Write the flow for it.
- **Study (C, G):** T49 vs T21. Options: the accessibility mirror lists delete for every row
  regardless of hover (presence then has two surfaces, pointer and accessibility), or delete
  gets a keyboard path (e.g. Delete key on a focused row). Either way it is a claim the web
  version never made; call it out as an extension.
- **Study (C, D):** T29/T31 are about event ordering between Escape and blur. In Cairn, blur is
  an `Event` the runtime turns into an `Action`; make "leaving edit mode" remove the field from
  focus without emitting a commit, and prove that Escape followed by any event sequence leaves
  the title unchanged.
- **Avoid (I):** copying web structure (`#main`, `<strong>`, classes). The claims talk about
  what a person sees and does; selectors are Quickstrom's and Cypress's problem.
- **Conformance (J):** the Cypress suite is a free list of concrete scenarios. Port each `it`
  to a flow with a witness path; it is a cheap cross-check that the generated sequences cover
  what the maintainers test.
