module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Examples.Todo.Model
public import Examples.Todo.View
public import Cairn.Text.Host
public import Cairn.Layout.Core
public import Cairn.Runtime.Abi
public import Cairn.Frame.Boundary

/-! # TodoMVC

The app (workstream I, GOAL.md M1): the claims over `Examples.Todo.Model`, the machine they
make, and the v1 ABI. `update` is `machine.update`, built from these moves and nothing else. The
view is `Examples.Todo.View`; theorems about it (presence, pressability) are in
`Examples.Todo.Proofs`, runtime checks in `Examples.Todo.Tests`, the mapping from the TodoMVC
requirements (`research/todomvc`, T1–T50) to these ids in `Examples/Todo/README.md`, and the
host in `host/Sources/CairnTodo`.

| Id | Kind | What |
|---|---|---|
| ^201 | place | the window |
| ^202 | move | the new-todo field: edits, and Enter adds |
| ^203 | move | toggle all |
| ^204 | move, keyed | a todo's checkbox |
| ^205 | move, keyed | double-click a todo's title to edit it |
| ^206 | move, keyed | a todo's delete button |
| ^207 | move, keyed | a todo's edit field: edits; Enter or blur saves, Escape cancels |
| ^208–^210 | move | the filters All, Active, Completed |
| ^211 | move | Clear completed |
| ^212 | invariant | the counter is the number of active todos; ids are distinct |
| ^213 | invariant | the listed rows are the todos the filter accepts, in order |
| ^214 | assume | the host reports a double click as a second click |
| ^215 | retired | hash routes and the back button (web only) |
| ^216–^224 | flow | witnessed paths through the app | -/

@[expose] public section

namespace Examples.Todo
open Cairn Cairn.Claims

/-! ## Claims -/

place ^201 window "Todos window" where
  does "The window: the heading, toggle all and the new-todo field, the listed todos, the footer with the counter, filters and Clear completed, and the info line."

move ^202 newTodo (s : State) "New todo" in ^201 where
  does "Type in the What needs to be done? field, and press Enter. (T5–T13)"
  sees "The text appears in the field. Enter adds the trimmed text as an active todo at the end of the list and clears the field; blank text adds nothing and stays in the field. Nothing else changes."
  on edit (op : TextOp)
    emit := ({ s with newField := (Text.Field.apply op s.newField).1 },
      (Text.Field.apply op s.newField).2)
    post s' := s'.newField = (Text.Field.apply op s.newField).1 ∧ s'.todos = s.todos ∧
      s'.left = s.left ∧ s'.nextId = s.nextId ∧ s'.filter = s.filter ∧ s'.editing = s.editing
    sound := by intro s op; exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
  on submit
    apply := add s
    post s' := Added s s'
    sound := by intro s; exact add_added s

move ^203 toggleAllTodos (s : State) "Mark all as complete" in ^201 where
  does "Press the toggle-all checkbox. (T14–T17)"
  sees "Every todo, listed or not, is completed; or, when all were completed already, every todo is active again. The pending new-todo text and the filter don't change."
  enabled := !s.todos.isEmpty
  on press
    apply := toggleAll s
    post s' := s'.todos = s.todos.map (setDone (!allDone s)) ∧ s'.newField = s.newField ∧
      s'.filter = s.filter
    sound := by intro s _; exact ⟨rfl, rfl, rfl⟩

move ^204 toggleTodo (s : State) (k : Nat) "Complete a todo" in ^201 where
  does "Press a todo's checkbox. (T19, T42)"
  sees "The todo is completed, or active again; the counter follows, and under a filter it leaves or joins the list. Nothing else changes."
  enabled := shown s k && !isEditing s k
  on press
    apply := toggle k s
    post s' := s'.todos = s.todos.map (flip k) ∧ s'.newField = s.newField ∧
      s'.filter = s.filter ∧ s'.editing = s.editing
    sound := by
      intro s k h
      have hk : has s k = true := has_of_shown (Bool.and_eq_true _ _ ▸ h).1
      obtain ⟨h1, h2, h3, -⟩ := toggle_frame k s
      exact ⟨toggle_todos k s hk, h1, h2, h3⟩

move ^205 startEditing (s : State) (k : Nat) "Edit a todo" in ^201 where
  does "Double-click a todo's title. (T20, T25–T27)"
  sees "The todo's row becomes a field holding its title, with the caret at the end and keyboard focus in it; any other todo in edit mode is replaced. Nothing else changes."
  enabled := shown s k && !isEditing s k
  on doublePress
    emit := (startEdit k s, [.focus (editRef k)])
    post s' := Started k s s'
    sound := by
      intro s k h
      have hk : has s k = true := has_of_shown (Bool.and_eq_true _ _ ▸ h).1
      exact startEdit_started k s hk

move ^206 deleteTodo (s : State) (k : Nat) "Delete a todo" in ^201 where
  does "Press a todo's delete button (×, drawn while the pointer is over the row or the button has keyboard focus). (T21, T22, T49)"
  sees "The todo is gone, with its row. Nothing else changes."
  enabled := shown s k && !isEditing s k
  on press
    apply := delete k s
    post s' := s'.todos = s.todos.filter (·.id ≠ k) ∧ s'.newField = s.newField ∧
      s'.filter = s.filter ∧ s'.editing = s.editing
    sound := by
      intro s k h
      have hk : has s k = true := has_of_shown (Bool.and_eq_true _ _ ▸ h).1
      obtain ⟨h1, h2, h3, -⟩ := delete_frame k s
      exact ⟨delete_todos k s hk, h1, h2, h3⟩

move ^207 editTodo (s : State) (k : Nat) "Edit field" in ^201 where
  does "In edit mode, type in the todo's field; then press Enter, click elsewhere or Tab away, or press Escape. (T28–T31, T50)"
  sees "Enter, a click elsewhere and Tab save: the trimmed text becomes the title, or the todo is deleted when it is blank. Escape leaves the title exactly as it was. Edit mode ends either way; after Enter or Escape keyboard focus returns to the new-todo field."
  enabled := shown s k && isEditing s k
  on edit (op : TextOp)
    emit := editApply op s
    post s' := (∀ e, s.editing = some e →
        s'.editing = some { e with field := (Text.Field.apply op e.field).1 }) ∧
      s'.todos = s.todos ∧ s'.left = s.left ∧ s'.newField = s.newField ∧ s'.filter = s.filter
    sound := by intro s k op _; exact editApply_post op s
  on submit
    emit := (commit s, [.focus newRef])
    post s' := Committed k s s'
    sound := by
      intro s k h
      exact commit_committed k s (of_decide_eq_true (Bool.and_eq_true _ _ ▸ h).2)
  on blur
    apply := commit s
    post s' := Committed k s s'
    sound := by
      intro s k h
      exact commit_committed k s (of_decide_eq_true (Bool.and_eq_true _ _ ▸ h).2)
  on cancel
    emit := (cancel s, [.focus newRef])
    post s' := s'.editing = none ∧ s'.todos = s.todos ∧ s'.left = s.left ∧
      s'.newField = s.newField ∧ s'.filter = s.filter
    sound := by intro s k _; exact ⟨rfl, rfl, rfl, rfl, rfl⟩

move ^208 showAll (s : State) "All" in ^201 where
  does "Press the All filter. (T39–T43)"
  sees "Every todo is listed; only the filter changes."
  enabled := !s.todos.isEmpty
  on press
    apply := setFilter .all s
    post s' := s' = { s with filter := .all }
    sound := by intro s _; rfl

move ^209 showActive (s : State) "Active" in ^201 where
  does "Press the Active filter. (T39–T43)"
  sees "Only active todos are listed; only the filter changes."
  enabled := !s.todos.isEmpty
  on press
    apply := setFilter .active s
    post s' := s' = { s with filter := .active }
    sound := by intro s _; rfl

move ^210 showCompleted (s : State) "Completed" in ^201 where
  does "Press the Completed filter. (T39–T43)"
  sees "Only completed todos are listed; only the filter changes."
  enabled := !s.todos.isEmpty
  on press
    apply := setFilter .completed s
    post s' := s' = { s with filter := .completed }
    sound := by intro s _; rfl

move ^211 clearDone (s : State) "Clear completed" in ^201 where
  does "Press Clear completed, shown while some todo is completed. (T37, T38)"
  sees "Every completed todo is removed, listed or not; active todos stay in order, and the button disappears."
  enabled := anyDone s
  on press
    apply := clearCompleted s
    post s' := s'.todos = s.todos.filter (!·.completed) ∧ s'.newField = s.newField ∧
      s'.filter = s.filter ∧ s'.left = s.left
    sound := by intro s _; exact ⟨rfl, rfl, rfl, rfl⟩

/-- TodoMVC's behaviour: its moves, from an empty list. -/
def machine : Machine State := { init := {}, moves := moves% }

invariant ^212 counterAndIds "Counter and ids" for machine where
  does "The counter shows the number of active todos, over all todos; todo ids are distinct, in every reachable state. (T24, T34)"
  holds s := Inv s
  init := init_inv
  step := machine.preserves <|
    Move.all_cons (newTodo.preserves _ (fun _ _ h => h) fun _ h => add_inv h)
      (Move.all_cons (toggleAllTodos.preserves _ fun _ _ h => toggleAll_inv h)
      (Move.all_cons (toggleTodo.preserves _ fun _ k _ h => toggle_inv k h)
      (Move.all_cons (startEditing.preserves _ fun _ k _ h => startEdit_inv k h)
      (Move.all_cons (deleteTodo.preserves _ fun _ k _ h => delete_inv k h)
      (Move.all_cons (editTodo.preserves _ (fun _ _ op _ h => editApply_inv op h)
          (fun _ _ _ h => commit_inv h) (fun _ _ _ h => commit_inv h) (fun _ _ _ h => h))
      (Move.all_cons (showAll.preserves _ fun _ _ h => h)
      (Move.all_cons (showActive.preserves _ fun _ _ h => h)
      (Move.all_cons (showCompleted.preserves _ fun _ _ h => h)
      (Move.all_cons (clearDone.preserves _ fun _ _ h => clear_inv h) Move.all_nil)))))))))

invariant ^213 listedRows "The list is the filter applied to the todos" for machine where
  does "The rows on screen are exactly the todos the selected filter accepts, in creation order, under any hover and focus, in every reachable state. (T40, T42)"
  holds s := ∀ ui, (view s ui).controls.filterMap rowKey = (visible s).map (·.id)
  init := fun ui => view_rows _ ui
  step := fun _ _ _ ui => view_rows _ ui

assume ^214 doubleClick "The host reports a double click as a second click" where
  does "The host sends the second click of a double click as a pointer down with a click count of 2, at the same point, within the system's double-click interval; the runtime turns its release into a double press. (T20)"

retire ^215 move "Back through filters" because "Web only (T46): hash routes and the back button walk the filter history in a browser. The Mac app has no filter history and no Back command."

flow ^216 addAndComplete "Add two todos and complete one" for machine where
  does "Type milk and press Enter, type eggs with spaces around it and press Enter, then check milk."
  sees "Two todos in order, eggs trimmed, milk completed, the field empty, and 1 item left."
  goal s := s.todos.map (·.title) = ["milk", "eggs"] ∧
    s.todos.map (·.completed) = [true, false] ∧ s.left = 1 ∧ s.newField.text = []
  witness edit ^202 (.insert "milk"), submit ^202, edit ^202 (.insert "  eggs "), submit ^202,
    press ^204#1

flow ^217 blankAddsNothing "Blank text adds nothing" for machine where
  does "Type spaces and press Enter."
  sees "No todo, and the spaces stay in the field (T8)."
  goal s := s.todos = [] ∧ s.newField.text = "   ".toList
  witness edit ^202 (.insert "   "), submit ^202

flow ^218 editAndSave "Edit a todo and save with Enter" for machine where
  does "Add milk, double-click it, select all, type oat milk with spaces around it, press Enter."
  sees "The title is oat milk, trimmed, and edit mode has ended."
  goal s := s.todos.map (·.title) = ["oat milk"] ∧ s.editing = none
  witness edit ^202 (.insert "milk"), submit ^202, doublePress ^205#1,
    edit ^207#1 .selectAll, edit ^207#1 (.insert " oat milk "), submit ^207#1

flow ^219 editToBlankDeletes "Saving a blank edit deletes the todo" for machine where
  does "Add milk, double-click it, delete its text, and click elsewhere."
  sees "The todo is gone (T29, T30)."
  goal s := s.todos = [] ∧ s.editing = none ∧ s.left = 0
  witness edit ^202 (.insert "milk"), submit ^202, doublePress ^205#1,
    edit ^207#1 .selectAll, edit ^207#1 .deleteBackward, blur ^207#1

flow ^220 escapeCancels "Escape cancels an edit" for machine where
  does "Add milk, double-click it, delete its text, press Escape."
  sees "The title is still milk, and edit mode has ended (T31)."
  goal s := s.todos.map (·.title) = ["milk"] ∧ s.editing = none
  witness edit ^202 (.insert "milk"), submit ^202, doublePress ^205#1,
    edit ^207#1 .selectAll, edit ^207#1 .deleteBackward, cancel ^207#1

flow ^221 activeFilter "The Active filter hides completed todos" for machine where
  does "Add milk and eggs, check milk, press Active."
  sees "Only eggs is listed, and the counter still says 1 item left (T40, T42)."
  goal s := (visible s).map (·.title) = ["eggs"] ∧ s.left = 1 ∧ s.todos.length = 2
  witness edit ^202 (.insert "milk"), submit ^202, edit ^202 (.insert "eggs"), submit ^202,
    press ^204#1, press ^209

flow ^222 clearCompletedFlow "Clear completed" for machine where
  does "Add milk and eggs, check milk, press Clear completed."
  sees "Only eggs remains, and Clear completed is gone (T37, T38)."
  goal s := s.todos.map (·.title) = ["eggs"] ∧ anyDone s = false
  witness edit ^202 (.insert "milk"), submit ^202, edit ^202 (.insert "eggs"), submit ^202,
    press ^204#1, press ^211

flow ^223 markAllComplete "Mark all as complete, then undo it" for machine where
  does "Add milk and eggs, check milk, press toggle all twice."
  sees "After the first press every todo is completed and the counter says 0 items left; after the second every todo is active again (T16, T35)."
  goal s := s.todos.map (·.completed) = [false, false] ∧ s.left = 2
  witness edit ^202 (.insert "milk"), submit ^202, edit ^202 (.insert "eggs"), submit ^202,
    press ^204#1, press ^203, press ^203

flow ^224 addUnderCompleted "A new todo under the Completed filter" for machine where
  does "Add milk, press Completed, add eggs."
  sees "Eggs is created but not listed, since it is active; the filter stays Completed (T11, T12)."
  goal s := s.todos.length = 2 ∧ visible s = [] ∧ s.filter = .completed
  witness edit ^202 (.insert "milk"), submit ^202, press ^210, edit ^202 (.insert "eggs"),
    submit ^202

/-- Every claim TodoMVC makes. -/
def claimInfos : List ClaimInfo := claims%

/-- At launch, keyboard focus is in the new-todo field (T5). -/
def app : App State := machine.toApp view claimInfos (some newRef)

/-! ## The app ABI (docs/runtime.md) -/

/-- Core Text metrics in the running app (the Swift host links `cairn_text_metrics`). -/
def cfg : Runtime.Config := { metrics := TextMetrics.host }

@[export cairn_app_init]
def appInit (w h scalePercent : UInt32) : Runtime.State State :=
  Runtime.initState app cfg w h scalePercent

@[export cairn_app_step]
def appStep (s : Runtime.State State) (events : ByteArray) : Runtime.State State :=
  Runtime.stepBytes app cfg Frame.boundary s events

@[export cairn_app_frame]
def appFrame (s : Runtime.State State) : ByteArray := Runtime.frameBytes Frame.boundary s

end Examples.Todo
