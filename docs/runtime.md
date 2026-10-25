# The interaction runtime

`lean/Cairn/Runtime/` is the generic loop every app runs on. It owns hit testing, hover, press
tracking, focus and keyboard routing, turns host `Event`s into the `Action`s an app's `update`
sees, and re-runs `view` and layout after each one. Apps never see raw input: every action
names a control on screen, and every control names a claim.

| File | What |
|---|---|
| `Hit.lean` | `Target`, hit entries, `hitTarget`/`hitTest`, `Reaches`, `LayoutFacts`, hit-level pressable |
| `Step.lean` | `Config`, `State`, `route`, `settle`, `step`, `steps`, `start`, `cursor` |
| `Proofs.lean` | soundness of focus/hover/press, no action without a control, step-level pressable |
| `ScrollProofs.lean` | the clamp, a scroll leaves the app alone, appear exactly, Tab reveals |
| `Abi.lean` | `Boundary`, `initState`, `stepBytes`, `frameBytes` (the Lean side of the app ABI) |
| `Tests.lean` | `#guard` checks on a small app |

## State

```lean
structure Config where
  metrics : TextMetrics := TextMetrics.mono
  layout : TextMetrics → Size → Node → Laid := Cairn.Layout.layout

structure State (S : Type) where
  app : S              -- the app's state
  ui : UI              -- size, hover, pressed, focus, window focus, scroll offsets; `view` reads it
  clicks : Nat         -- click count of the pointerDown that started the press
  pointer : Option Point
  scale : Nat          -- backing scale × 100
  laid : Laid          -- the tree on screen; hit testing reads this
  effects : Array Effect  -- effects of the last `stepBytes` batch
  world : World        -- clock, timers, pending requests, active subscriptions (effects.md)
  subCmds : Array SubCmd  -- subscription commands of the last `stepBytes` batch
  surfaces : List Shown   -- what each surface shows (docs/surfaces.md)
  seen : List ControlRef  -- the `appear` controls that showed at the last frame event
```

## Hit testing

Paint order is pre-order: a node paints before its children, children in list order, so later
is on top. Every node that paints leaves a **hit entry** — a box with a background, border or
control, every text run, every field — holding its visible rect (`rect.inter clip`) and its
**owner**, the nearest control at or above it. Unpainted, control-less boxes are layout only
and leave nothing.

`hitTarget laid p` is the owner of the topmost entry containing `p`. So a label inside a button
routes to the button, and an opaque panel painted over a button blocks it (the hit goes to the
panel's owner, usually none). This is a little stronger than "the topmost control whose visible
rect contains the point": that rule lets a click through anything without a control.
`hitTest : Laid → Point → Option Control` is `hitTarget` projected to the control. Fields are
controls.

## Events

`route` reads one event against `s.laid` (the tree the person sees) and returns the new
interaction state and the actions to deliver, in order. Events from the outside world
(`clock`, `reply`, `subEvent`) route to no actions; `admit` handles them first: it advances the
clock (the first clock boots the app: it hears the time, then `app.initEffects` run), fires due
timers, and delivers a valid reply or an active subscription's event to `app.receive`, hearing
the current time before any delivery (docs/effects.md, "Order within a step"). Then `step`:

1. folds `app.update` over the actions (`act`), hearing the clock first if the app hasn't,
   collecting effects; every effect is absorbed into the world as it is returned (timers set
   and cancelled, requests admitted to the pending table or refused); if an effect is
   `focus c` (the last one wins), sets `ui.focus := some c`. This is how an app moves keyboard
   focus (into a field it just showed, back to a field after a commit). No `blur` is delivered
   for a field the request takes focus from, and step 3 drops the focus if `c` is not a
   focusable control of the new tree. The effect still rides on the frame; the host ignores it;
2. re-runs `view` with the new `UI` and lays it out (`relayout`);
3. repairs the `UI` against the new tree (`fixUI`): hover becomes whatever the pointer is over
   now, focus survives only if its control is still there and focusable, press only if its
   control is still there, and each scroll offset only if its box is still there, clamped to
   it (see "Scrolling");
4. if the repair changed what `view` saw (a hover reveal, a focus ring), views and lays out
   again, up to `settleFuel` (2) more times (`settle`). The stored `UI` is always the routed one
   repaired against the stored tree, so the soundness theorem holds whether or not it converged.

If anything was delivered, `step` then diffs `app.subscriptions` against the active set and
records the commands for the frame (`diffSubs`). If an event delivers nothing and leaves the
`UI` unchanged, `step` skips view and layout; only the world changes.

### Pointer (primary button; the secondary button only moves hover)

| Event | Effect |
|---|---|
| `pointerMove p` | hover := control at `p`. If a focused field is pressed (a drag that started in it): `edit c (setCaret i true)` |
| `pointerDown p` on a field `c` | blur the previously focused field if it was another one; focus := `c`; pressed := `c`; `edit c (setCaret i shift)` where `i` is the boundary nearest the click |
| `pointerDown p` on another control `c` | blur the focused field, if any; focus := none; pressed := `c`; remember the click count |
| `pointerDown p` on nothing | blur the focused field, if any; focus := none; pressed := none |
| `pointerUp p` on the pressed control, not a field | `press c`, or `doublePress c` when the down had clicks = 2 |
| `pointerUp p` anywhere else | nothing (slide-off cancels); pressed := none either way |
| `pointerExit` | hover := none; the pointer is forgotten |
| `scroll p dx dy` | moves the innermost scroll box under `p` by `dy` (a row: `dx`), clamped; no action (see "Scrolling") |

The caret index from a click is the nearest entry of `metrics.offsets font text` to
`p.x - textOrigin.x`, the earlier on a tie. A double click therefore delivers `press` then
`doublePress` (macOS sends both downs). Double and triple clicks in a field only place the
caret: word selection needs a `TextOp` that doesn't exist yet.

Cursor: `cursor s` is `text` over a field, `pointer` over any other control, `arrow` otherwise.

### Keyboard and text

Focus is a `ControlRef`; it's looked up in `s.laid` each time. Every field is focusable; other
controls are unless their role is `group`, `text`, `heading` or `list`.

- **Tab / shift-Tab** move focus to the next / previous focusable control in paint order,
  wrapping; from no focus, to the first / last. Leaving a field delivers `blur`; entering a
  field delivers `edit c selectAll`.
- **Focused field `c`:** Enter → `submit c`, Escape → `cancel c`, and editing keys →
  `edit c op`:

  | Key | op |
  |---|---|
  | backspace / delete | `deleteBackward` / `deleteForward`; option: word; command: `moveHome true`/`moveEnd true` then delete |
  | left / right | `moveLeft` / `moveRight`; option: word; command: `moveHome` / `moveEnd` (shift extends) |
  | up, home, page up / down, end, page down | `moveHome` / `moveEnd` (single-line fields) |

  `insertText s`, `setMarked`, `unmark`, `copy`, `cut`, `paste s`, `selectAll`, `undo`, `redo`
  → `edit c` with the matching op. Command shortcuts arrive as those events (the host's edit
  menu), not as `key (char _)`.
- **Replacement ranges.** `insertText s (some (a, b))` and `setMarked … (some (a, b))` first
  select `[a, b)`: `edit c (setCaret a' false)`, `edit c (setCaret b' true)` with `a'`, `b'`
  clamped to the field's text length, then the insert or composition.
- **Focused button-like control `c`:** Enter or space (`insertText " "`) → `press c`.
- Nothing focused: keys and text do nothing, except the scroll keys (see "Scrolling").

Blur is delivered only for fields (it's how an edit is committed); focus moving between buttons
is UI state only. When a focused control disappears from the tree, focus is dropped without a
`blur` (there is no control left to name).

At launch, `start` focuses `app.initFocus` (default `none`) if it is a focusable control of the
first tree.

### Window

`resize` sets `ui.size`, `scale` sets `State.scale`, `windowFocus b` sets `ui.windowFocused` and,
when the window loses focus, clears the press (its pointerUp won't arrive).

## Scrolling

The runtime owns the offset of every scroll box (docs/layout.md, "Scroll boxes") that names
itself with `Style.scrollRef`, as it owns focus: offsets live in `UI.scroll : List (ControlRef ×
Int)`, keyed by the box's ref, and the view reads them. A box's ref is usually a `place`
claim's (`⟨14, 0⟩` in the fixture); it is not a control and has no move.

```lean
.box (ui.scrolling rowsRef { height := .fixed 160 }) none rows
-- = { scroll := some (ui.scrollOf rowsRef), scrollRef := some rowsRef, .. }
```

A box with no offset yet is at 0. What moves an offset:

- **The wheel and the trackpad.** `scroll p dx dy` moves the innermost box whose visible part
  holds `p` (the last in paint order, `scrollerAt`) by `dy`, or by `dx` in a row. Positive is
  toward the end of the content (the host's sign, trusted as ^1012). A box at its end doesn't
  pass the rest to the box around it.
- **Keys**, when no control takes them: nothing is focused, or the focused control is not a
  field and the key isn't Enter or space. They move the innermost box around the focused control,
  else the box under the pointer. Page Down / Page Up and space / shift-space move a page (the
  viewport less a 40-point line, at least a line); Home and End go to the ends; the arrows along
  the box's axis move a line, with command to the ends.
- **Tab.** Focusing a control by Tab moves every box around it, innermost first, by the least
  that puts the control wholly in view (its start, if it is longer than the box): `revealIn`.
  Focus by click or by `Effect.focus` doesn't scroll.

Every offset is clamped to `[0, max 0 (content − viewport)]`, where `viewport` is the box's
length along its axis and `content` the distance from its unscrolled start to the furthest
child's end plus the end padding (`Scroller`). The clamp is in `fixUI`, so it holds after every
step, against the tree just laid: when content shrinks, the offset follows it. An offset whose
box has left the tree is dropped. A scroll is never an action: `update` never sees it, and the
app's state, the world and the effects are unchanged by it (`step_scroll`).

## Appear

A control with `Control.appear := true` tells the app when it comes on screen: the runtime
delivers `Action.appear c`, a move like any other (trigger `appear`, `on appear` in a move), when
`c` has a visible part (`rect ∩ clip` nonempty) and didn't at the last frame, or wasn't in the
tree. It is how an app hears that the end of a list is in view and loads more.

"The last frame" is the end of the last batch. `steps` runs a batch's events, then two
`Event.frame`s (`frameEvents`). A frame event is the runtime's own: the host never sends one, it
has no encoding, and nothing else routes to it. It compares the appear controls showing now
(`appearRefs`) with `State.seen`, the ones that showed at the last frame event, delivers an
`appear` for each new one in paint order, and records the current ones. The second frame event
hears what the first one's delivery brought on screen. So a control that comes and goes within
one batch is never heard, and one that stays on screen is heard once, until it leaves.

A control is on screen only while its move is enabled (each app's presence claims), so `appear`
fires when a marked control becomes visible, or becomes enabled while visible.

## Theorems

All in `Cairn.Runtime`; none assume anything about the layout function.

- **Pressable, hit level.** `hitTest_center : LayoutFacts laid t → hitTest laid t.visible.center
  = some t.control`, from the general `hitTarget_of_reaches : Reaches laid t p → hitTarget laid
  p = some t`.
- **Pressable, step level.** `click_presses`: if `p` reaches a non-field control `t` in
  `s.laid`, and after the pointerDown (and the update and relayout it causes) `p` still reaches a
  non-field control with `t`'s ref, then the pointerDown delivers only blurs and the pointerUp
  delivers exactly `[press t.ref]`. `click_center_presses` is the same at the centre under
  `LayoutFacts`. Supporting: `down_actions`, `step_down_pressed`.
- **No action without a control.** `route_names`: every action `route` produces names a control
  of `s.laid`; `step_delivers`: those are exactly the actions `step` passes to `update`, in order.
- **Focus is sound.** `start_sound`, `step_sound`, `steps_sound`: focus is none or a focusable
  control of the tree on screen; hover and press are none or controls of it.
- **M1 apps are unchanged.** `step_delivers_quiet`: for an app whose `receive` ignores every
  message, a step's state is what folding `update` over the routed actions gives, as before.
- **Offsets are clamped.** `start_clamped`, `step_clamped`, `steps_clamped`: every offset in
  `ui.scroll` belongs to a scroll box of the tree on screen and lies within `[0, max 0 (content
  − viewport)]` of it (`Clamped`).
- **A scroll changes no app state.** `step_scroll`: a `scroll` event leaves the app's state and
  the world unchanged and issues no effects. Appear moves come only from frame events
  (`route_appear`).
- **Appear, exactly.** `appear_iff`: a frame event routes `appear c` exactly when `c` is an
  `appear` control with a nonempty visible part now and was not one at the last frame event;
  `step_frame_seen`, `step_seen_other`: only a frame event changes `seen`, to the current
  ones; `step_frame_delivers`: `update` gets those moves, in order.
- **Tab reveals.** `revealOff_shows`: from a clamped offset, the new offset puts a rect that
  fits in the box wholly inside it.
- **Time, timers, replies, subscriptions.** `step_clock`, `steps_book`, `step_reply`,
  `step_sub_ignored`, `diffSubs_*`: see docs/effects.md, "Theorems".

### `LayoutFacts` (what B proves about its trees)

```lean
def Reaches (laid : Laid) (t : Target) (p : Point) : Prop :=
  ∃ pre post, hits laid = pre ++ ⟨t.visible, some t⟩ :: post ∧ t.visible.contains p ∧
    ∀ h ∈ post, h.visible.contains p → h.owner = some t

structure LayoutFacts (laid : Laid) (t : Target) : Prop where
  nonempty : t.visible.nonempty
  reaches : Reaches laid t t.visible.center
```

In words: the control's visible rect is nonempty, and everything painted after it that covers
its centre belongs to it. "Clips nest" is not needed: the runtime reads each node's own `clip`.

The step-level theorem also needs the fact after the pointerDown's relayout, because `view` may
read `ui.pressed`. For an app whose view at a given size doesn't move the control when it's
pressed, that's the same layout fact again.

## The app ABI

One app per binary. The app file exports three wrappers (all arguments owned: Lean 4.35 rejects
`@&` on `@[export]`):

```lean
@[export cairn_app_init]
def appInit (w h scalePercent : UInt32) : Runtime.State App.State :=
  Runtime.initState App.app cfg w h scalePercent
@[export cairn_app_step]
def appStep (s : Runtime.State App.State) (events : ByteArray) : Runtime.State App.State :=
  Runtime.stepBytes App.app cfg boundary s events
@[export cairn_app_frame]
def appFrame (s : Runtime.State App.State) : ByteArray := Runtime.frameBytes boundary s
```

In C:

```c
lean_object *cairn_app_init(uint32_t w, uint32_t h, uint32_t scale_percent);
lean_object *cairn_app_step(lean_object *state, lean_object *events); // consumes both
lean_object *cairn_app_frame(lean_object *state);                     // consumes state
```

- `w`, `h` are logical points; `scale_percent` is the backing scale × 100.
- `cairn_app_step` consumes the state and the event bytes and returns the new state; the host
  drops its old reference. To keep the state across `cairn_app_frame`, `lean_inc` it first.
- `events` is a batch, decoded by `Boundary.decode` and run in order (`steps`).
- The frame carries the effects and subscription commands of the most recent `cairn_app_step`,
  and the earliest timer's deadline as `wake`. The host requests one
  frame after each step and runs its effects once; a second frame of the same state repeats them.
- `cfg.metrics` is `TextMetrics.mono` until F's Core Text metrics land (`@[extern]` in
  `Cairn/Text/Host.lean`); `cfg.layout` defaults to `Cairn.Layout.layout` (docs/layout.md).

`Boundary` is the interface to E:

```lean
structure Boundary where
  decode : ByteArray → List Event
  render : Laid → UI → Canvas      -- Frame.ofLaid; the runtime fills the cursor
  encode : Frame → ByteArray
```

`Cairn.Frame.boundary` (`Cairn/Abi.lean`) is the real one: v2 event decoding,
`Frame.ofLaid` and v3 frame encoding ([frame.md](frame.md)). `render` takes the whole `UI` because
the canvas needs the focus (accessibility `focused`, the caret, the text-input state) as well
as the size. `Boundary.frame` (`Runtime/Abi.lean`) builds one surface record per surface the
runtime shows (`State.surfaces`, docs/surfaces.md) and adds the effects, subscription commands
and wake. A batch that fails to decode is dropped whole.
