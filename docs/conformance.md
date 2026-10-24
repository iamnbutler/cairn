# Conformance

[M1](goals/m1.md), "Done means" item 5: sequences of moves are generated from the Lean model and performed
on the running app as real input. After every step, the app's frame, accessibility tree, effects
and pixels are compared with the model's.

```sh
make conformance APP=Basics            # N=1000 walks of LEN=12 steps, SEED=1
make conformance APP=Basics N=50 LEN=20 SEED=7
```

The run writes:

- `build/conformance/<App>.json`, which the map reads (docs/map.md);
- `build/conformance/<App>/report.md`, with a shrunk repro for each distinct failure;
- `failures.jsonl`;
- the app's log.

The exit status is non-zero if anything failed.

The run has three parts:

| Part | Where | What it does |
|---|---|---|
| Debug socket | `host/Sources/CairnHost/Debug*.swift` | drives one running app and reads back what it shows |
| Generator | `tools/conformance/lean/` (`Conformance.Gen`, plus one file per app) | walks the model and writes, for each step, the gestures and the frame the app must then show |
| Driver | `tools/conformance/driver.ts` (bun) | replays the sequences on the app through the socket, compares, and writes the results |

## Adding an app

Adding an app takes one file, `tools/conformance/lean/Conformance/Apps/<App>.lean`:

```lean
module
public import Conformance.Gen
public import Examples.Todo
@[export cairn_conformance_run]
public def Conformance.Apps.Todo.run (args : List String) : IO UInt32 :=
  Conformance.run Examples.Todo.machine Examples.Todo.app Examples.Todo.cfg args
```

The app must also be in the Makefile's `APPS`, and its host target must be `Cairn<App>`. Its
claims are read with `lake exe claims Examples.<App>`.

## The debug socket

The socket is off by default. Any of these turns it on:

- `CAIRN_DEBUG_SOCKET=1`, which puts it at `$TMPDIR/cairn-<title>-<pid>.sock`;
- `CAIRN_DEBUG_SOCKET=<path>`;
- `--debug-socket [path]`.

It is a Unix socket, created with mode 0600 and removed when the app quits. Requests and replies
are one JSON object per line, and every reply carries `ok`, plus `error` when `ok` is false.

| Command | Does | Reply |
|---|---|---|
| `{"cmd":"hello"}` | | title, pid, window number, logical size, scale×100, clear colour, last input seq |
| `{"cmd":"pointer","type":"move"\|"down"\|"up"\|"exit","at":[x,y],"clicks":n}` | `mouseMoved`/`mouseDragged`, `mouseDown`, `mouseUp`, `mouseExited` on the view | `seq` |
| `{"cmd":"key","key":"left","mods":["shift"],"char":" "}` | `keyDown` on the view | `seq` |
| `{"cmd":"text","op":"insert"\|"marked"\|"unmark","text":…,"sel":[start,len]}` | `insertText`, `setMarkedText` or `unmarkText` (`NSTextInputClient`); `sel` is in scalars | `seq` |
| `{"cmd":"menu","name":"copy"…}` | `NSApp.sendAction(copy:, to: view)`, as the Edit menu does | `seq` |
| `{"cmd":"menu","place":P}` (no `name`) | | status item `P`'s `NSMenu` as AppKit holds it: per item `kind`, `title`, `enabled`, `state`, `id` (`^N#K`, a submenu's `^P`), `key`, `mods`, `items` |
| `{"cmd":"menuOpen","place":P}`, `{"cmd":"menuClose",…}` | the menu delegate's `menuWillOpen` / `menuDidClose` on the root menu | `seq` |
| `{"cmd":"menuSelect","place":P,"id":"^N#K"}` | an enabled item through `NSMenu.performActionForItem(at:)`; a greyed-out item's action sent directly (`"direct":true`), as when the menu changed while open | `seq` |
| `{"cmd":"menuSelect","place":P,"ref":[N,K]}` | a `menuSelect` event with any ref | `seq` |
| `{"cmd":"surfaces"}` | | activation policy, key window, main menu, and each surface: kind, place, shown, and its AppKit object (status item, panel properties and frame) |
| `{"cmd":"wait","seq":n}` | waits until a frame through input `n` is applied on the main thread | the frame's `seq`, `version`, effects run since the last wait, new text-shadow divergences |
| `{"cmd":"frame"}` | | the applied frame, decoded, in the generator's JSON shape |
| `{"cmd":"ax"}` | | every accessibility element under the view, as `NSAccessibility` answers it |
| `{"cmd":"pixels","points":[[x,y],…]}` | | colours of the presented drawable, or of an offscreen render if the window isn't drawing |
| `{"cmd":"restart"}` | the app restarts from its initial state | `seq` |
| `{"cmd":"snapshot","path":…}` | | writes the presented drawable as a PNG |
| `{"cmd":"quit"}` | | |

### How input arrives

Input is not posted to the window server. The socket builds real `NSEvent`s (mouse events with
the window's number and a location in its coordinates, key events with key code, characters and
modifier flags) and calls the view's own responder methods with them. Text and menu commands go
through the entry points AppKit itself calls. The events therefore cross the host's whole input
path: `HostView`, `interpretKeyEvents` and the key bindings, the selector table, the text-input
shadow, `Engine.send`, Lean, the frame, `applyLatestFrame`, the AX mirror and the renderer.

Nothing reaches any other app. Under the socket the app:

- runs as an accessory app (no Dock icon, no menu bar);
- is never activated;
- shows its window with `orderFrontRegardless`;
- sets `ignoresMouseEvents`, so the real mouse passes through it.

The driver doesn't need the app to be frontmost, and the person at the machine can keep working.
Pixels are read inside the app, from its own presented drawable (`DebugRenderer`). There is no
screen capture.

### Hooks

The socket changes four things about the app:

- **Effects.** An effect hook records every effect. A clipboard write goes to a private
  pasteboard (`cairn.debug.<pid>`) instead of the general one, and paste reads from it, so the
  user's clipboard is untouched. A beep is recorded and not sounded. A `quit` is recorded and not run.
- **Surfaces.** Status items and panels are built detached (`SurfaceHost` `.detached`): the menu
  is a real `NSMenu` but nothing is added to the menu bar, and panels are never ordered onto the
  screen.
- **Restart.** `Engine.restart` re-runs `cairn_app_init` at the view's size and scale, ordered
  with input by seq. Sequences don't need a relaunch.
- **Renderer.** `DebugRenderer` replaces `MetalRenderer`. It uses the same `Renderer`, clear
  colour and layer setup, and blits each drawable into a shared texture before presenting it.
  The render thread waits for the GPU on each frame, which only happens under the socket.

## The generator

`Conformance.run` is linked with the app library and the host's Core Text metrics
(`CairnMetrics`), so the model measures text exactly as the app does. It evaluates the same
`Runtime.step` and `Runtime.frame` the app runs, from `initState` at the app's size and scale.
It doesn't import `Lean`. It is linked with system clang, not Lake (see the Makefile's comment).

A walk starts from the initial state. At each step the generator lists what a person could do
now, from the model's current frame:

- each enabled move's control:
  - a click at the centre for `press`;
  - a double-click for `doublePress`;
  - a click to focus a field;
- with the field focused:
  - typing, from a vocabulary that includes emoji, CJK, accents, blanks and long text;
  - 16 editing keys (arrows, Option and Command variants, Backspace, Delete, Home, End, Up, Down);
  - the six Edit-menu commands;
  - two IME compositions;
  - a click inside the field;
  - a drag-select;
  - Enter for `submit` and Escape for `cancel`;
- Enter and Space on a focused button;
- plain UI: Tab, Shift-Tab, the pointer leaving the window, a hover anywhere, a click on empty
  space.

The walk picks a group uniformly, where a group is one control's trigger, or plain UI. Editing the
focused field gets three times the weight. Then the walk picks a choice within the group.

For each step the generator records:

- the gestures;
- the events the host should send (docs/host.md, "Input");
- the actions `Runtime.route` delivers, and whether each move accepts them;
- the effects;
- the full frame;
- pixel probes;
- model findings.

A pixel probe is a point inside each control's box where no text, border, corner or edge
antialiasing reaches, with the colour the frame's draws blend there.

The generator has two more modes:

- `--witness FILE` replays flows' witnesses from `lake exe claims`. A press is a click at the
  control's centre. An edit focuses the field, then types, pastes or deletes. Submit is Enter.
- `--gestures FILE` re-models raw gesture lists. The driver uses it to shrink failures.

## What is checked after every step

The driver performs the step's gestures, then waits until a frame through the last input's seq
is applied on the main thread. Then it checks:

| Check | Passes when |
|---|---|
| frame | the app's decoded frame equals the model's, value for value: every draw (rects, fills, radii, borders, text, font, colour, origin, clips), every AX node, the text input (text, selection, marked range, caret, origin) and the cursor |
| ax | the accessibility tree read through `NSAccessibility` equals the model's AX nodes through the host's table (docs/host.md, "Accessibility"): count and order, identifier (`^N#k`), role, subrole, role description, label, title, value, focused, selected, enabled, frame (screen coordinates mapped back to the view), parent; and for text fields, the selected range in UTF-16 and the character count |
| effects | the effects the host ran equal the model's |
| shadow | no new text-input shadow divergences: the host's prediction between an IME call and its frame agreed with Lean |
| pixels | each probe's colour in the presented drawable is within 3 per channel of the model's |
| model | the generator's findings are empty: every control on screen belongs to an enabled move, and a press delivered exactly that press (except a T33 dropped click, below) |

The initial frame, AX tree and pixels are checked after each restart. A sequence stops at its
first failing step. The states after that step have diverged, so later steps would only repeat
the failure.

**Known outcomes.** A press whose pointerDown delivers a `blur` and whose control is no longer
at the point after that step is dropped by the runtime (docs/runtime.md): the click ended an
edit, the blur saved it, and saving moved or removed the control, so the release presses
nothing. That is TodoMVC decision T33 (docs/plan.md), still open, and where
`Runtime.click_presses`'s hypothesis fails. The generator lists such a step under `known`
(`"T33: …"`), not `findings`: the app did what the model does, so the walk passes. The driver
counts them in the results file's `known` and in the claim's `known` and `note`, and
`report.md` lists them under "Known: open decisions", so the map can say so.

## Results file

`build/conformance/<App>.json` uses the map's shape (docs/map.md):

```json
{"runs": 1000, "commit": "2e63d83",
 "claims": {"^101": {"pass": true, "runs": 5899}, "...": {}},
 "sequences": {}, "steps": 12011, "probes": 27797, "triggers": {}, "timing": {}}
```

| Claim kind | `runs` is | It fails when |
|---|---|---|
| move | the steps that exercised it | any of those steps failed (the first failure becomes `note`) |
| flow | 1 | the replay of its witness from `lake exe claims` failed anywhere |
| invariant | every step checked | anything failed: it passes only when every state the app reached was the model's, where the invariant is proved |

A claim with known outcomes (above) has `known` (`{"T33": 1}`) and, when it passed, a `note`
naming the decision and the first walk and step. Places and assumptions aren't run; the map shows them as `n/a`. The extra fields (`sequences`,
`steps`, `probes`, `triggers`, `timing`, `plainUi`) are for people. The map reads only `claims`.

## Shrinking

For the first failure of each kind, the driver shrinks the failing sequence:

1. It takes the shortest failing prefix.
2. It tries dropping each earlier step, last to first. A drop is kept if the sequence still fails
   anywhere.
3. Each candidate is re-modelled from its gestures alone (`--gestures`) and replayed on the app.

The repro in `report.md` is therefore re-verified on the app, one step per line, in the
generator's gesture format.

## Basics

`make conformance APP=Basics N=1000` on this branch, rebased on b28cb50 (macOS 27, Apple silicon, debug build,
2x display) passed:

| | |
|---|---|
| Walks | 1000/1000 passed (12 steps each) |
| Flow witnesses | 3/3 passed (^107, ^108, ^109) |
| Steps | 12,011 |
| Actions delivered | 11,804 |
| Pixel probes | 27,797, all read from the presented drawable |
| ^101 (field) | 5,899 steps: 4,858 edits, 1,041 submits |
| ^102 (Add) | 2,858 presses |
| ^103 (toggle) | 175 presses |
| ^104 (delete) | 133 presses |
| Plain-UI steps | 2,935 |
| ^105 (invariant) | every step |
| Time | 146 s in all; per step p50 15.7 ms, p90 17.2 ms, max 27 ms |

Each step costs about one display refresh. The pixel read waits for the frame to be presented.

### Bugs found

None in Basics or the host.

The first runs found one bug in the driver itself. A synthesized Shift-Tab carried `"\t"` as
`charactersIgnoringModifiers`, and AppKit's key bindings read that field, so inside the field it
became `insertTab:` and focus moved forward. The model, given `key tab {shift}`, moved backward.
A real keyboard's Shift-Tab carries backtab (U+0019) in both fields. The socket now does the
same.

The shrunk repro was:

```
move 205 74, down 205 74 1, up 205 74
text  eggs
key enter -
key tab shift
```

This is the kind of mismatch the comparison exists to catch. Here the error was in the event we
built, not in the host.

## Counter

`make conformance APP=Counter N=1000` after Counter moved to the v1 ABI (commit 449e5e4, macOS 27,
Apple silicon, debug build, 2x display) passed:

| | |
|---|---|
| Walks | 1000/1000 passed (12 steps each) |
| Flow witnesses | 2/2 passed (^4, ^5) |
| Steps | 12,006 |
| Actions delivered | 7,004 |
| Pixel probes | 20,092, all read from the presented drawable |
| ^1 (Increment) | 4,886 steps |
| ^2 (Reset) | 2,118 steps |
| Time | 178.5 s in all; per step p50 16.5 ms, p90 17.3 ms, max 25.2 ms |

No failures. ^3 (place) and ^7 (assumption) aren't run. That run also checked invariant ^6 at
every step; ^6 has since been retired (its `pressed` field was vacuous on v1), and a rerun after
the retirement, `N=200`, passed 200/200 walks and both flows (2,406 steps, 4,037 probes, ^1 974
steps, ^2 419).

## Tray: menus

Tray (lean/Examples/Tray.lean) has no window: a status item with a native menu and an overlay
panel. The generator offers, for each shown status item:

- **open the menu**: `menuOpen` then `menuClose`, the move being a press on the item's control;
- **choose an item**: `menuSelect` for each item that is enabled (with every submenu around it)
  and whose move is enabled; the driver goes through `performActionForItem(at:)`;
- **choose a greyed-out item**: `menuSelect` for each other item, as a plain-UI step; the model
  expects nothing to change (`menu_select_stale`).

Window gestures (Tab, hover, clicking empty space) are offered only when the app has a window.
After every step the driver compares, besides the window's frame, each status item's menu (the
model's records printed in `DebugJSON.menu`'s shape: the host's key-equivalent table, and items in
a disabled submenu reported disabled, as AppKit reports them) with the socket's `menu`, and each
surface's kind, place and `shown` with `surfaces`. A flow witness's press on a status item's
control becomes open/close, and on a menu item a `menuSelect`.

`make conformance APP=Tray N=200` (macOS 27, Apple silicon, debug build) passed 200/200 walks
and both flows (^461, ^462): 2,404 steps; ^453 (open) 451, ^454 383, ^455 402, ^456 257, ^457
105, ^458 62, ^459 (Quit, recorded not run) 424. 87.8 s in all; per step p50 51.4 ms, p90 54.4
ms, max 62.4 ms, nearly all of it `performActionForItem`. Turning one model field wrong (a status
line reported enabled) fails every sequence at its initial frame with a `menus` problem.

Not covered: the real menu bar (clicking the status item, keyboard navigation in the open menu,
VoiceOver), and the panel's pixels (it has no AX nodes or probes; its canvas is checked through
the frame codec and Tray's self test). See [surfaces-checklist.md](surfaces-checklist.md).

Yap (`make conformance APP=Yap`) is driven the same way, with a silent world: every request
kind stays in flight (`silentWorld` in host/Sources/CairnYap/main.swift answers none, including
kinds added later, such as `makeDir`; before, a "no handler" reply to Open Transcripts Folder's
`makeDir` let the app go on to `open`, which the model, hearing nothing, never did). So its walks
stay in the menu, and `CONF_ARGS_Yap` passes `--invariants-unreached <why>`: the invariants are
reported `pass: null` with that reason, a gap on the map, rather than tested by states that
never exercise them.

## What it does not check

- **The window server.** Events are handed to the view, not routed by the window server or
  `NSWindow.sendEvent`. Window-level hit testing, key-window and first-responder routing, and
  `clickCount` timing aren't exercised; the socket sets `clickCount` itself.
- **Real input methods.** IME is driven through `NSTextInputClient` calls shaped like an input
  method's, not by a real Japanese or Chinese IME.
- **The user's key bindings.** Key equivalents go through `interpretKeyEvents` with the current
  user's key bindings. A custom `DefaultKeyBinding.dict` could change the results.
- **Timing.** Every step waits for its frame, so coalescing and input racing ahead of frames are
  not exercised.
- **Things Basics and Counter lack.** Scrolling, live resize and window focus (`UI.windowFocused`) aren't
  exercised.
- **The compositor.** Pixels come from the presented drawable, not the screen.
