# Conformance

[M1](goals/m1.md), "Done means" item 5: sequences of moves are generated from the Lean model and performed
on the running app as real input. After every step, the app's frame, accessibility tree, effects
and pixels are compared with the model's.

```sh
cd test/fixture && cairn conformance            # 1000 walks of 12 steps, seed 1
cd test/fixture && cairn conformance --n 50 --length 20 --seed 7
```

The run writes:

- `build/conformance/<App>.json`, which `cairn doc` reads (`tools/map/evidence.ts`);
- `build/conformance/<App>/report.md`, with a shrunk repro for each distinct failure;
- `failures.jsonl`;
- the app's log.

The exit status is non-zero if anything failed.

The run has three parts:

| Part | Where | What it does |
|---|---|---|
| Debug socket | `host/Sources/CairnHost/Debug*.swift` | drives one running app and reads back what it shows |
| Generator | `tools/conformance/lean/` (`Conformance.Gen`), plus one module per app (`<App>.Conformance`) | walks the model and writes, for each step, the gestures and the frame the app must then show |
| Driver | `tools/conformance/driver.ts` (bun) | replays the sequences on the app through the socket, compares, and writes the results |

## Adding an app

Adding an app takes one module beside it that exports `cairn_conformance_run`. The fixture's,
test/fixture/lean/Fixture/Conformance.lean:

```lean
module
public import Conformance.Gen
public import Fixture.Abi
public import Fixture.Fuzz
@[export cairn_conformance_run]
public def Fixture.Conformance.run (args : List String) : IO UInt32 :=
  _root_.Conformance.run Fixture.machine Fixture.app Fixture.cfg args (custom := Fixture.fuzz)
```

`custom` is optional. It is the app's `cairn fuzz` hook (`Cairn.Fuzz.Custom`, docs/fuzz.md), and
its `server` and `replies` answer the app's requests ("The world", below). The module that
defines it must be a `module` too. `cairn conformance` links the package's own modules that the
generator imports and the app's library doesn't hold, such as the fixture's `Fixture.Fuzz`.

The app package runs `cairn conformance` (docs/cli.md, "Checks"). Its module is
`<App>.Conformance` by default, in a `lean_lib` of its own declared after the app's (whose root
would otherwise claim it), as the fixture's is. `cairn conformance`
links it with the app's merged library (`.cairn/lib/lib<name>.a`) and the CairnRender and
CairnFrame objects of the app's own debug build, which carry the host's Core Text metrics.

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
| `{"cmd":"pointer","type":"rightDown"\|"rightUp","at":[x,y]}` | `rightMouseDown`, `rightMouseUp` on the view: a secondary click | `seq` |
| `{"cmd":"controlMenu"}` | | the open control menu as AppKit holds it (built, not popped up, under the socket): `owner`, `place`, `items` |
| `{"cmd":"controlMenuSelect","id":"^N#K"}` | an item of the open control menu through `performActionForItem(at:)` (a greyed one's action directly, `"direct":true`), then the close the host sends when a popped-up menu returns | `seq` |
| `{"cmd":"controlMenuClose"}` | the open control menu closes without a choice | `seq` |
| `{"cmd":"axShowMenu","id":"^N#K"}` | `AXShowMenu` on the control's accessibility element | `seq`, `performed` |
| `{"cmd":"menuBar"}` | | the app's own menu bar items as AppKit holds them: `appItems` at the top of the app menu, `menus` in the bar, and the whole main menu (`items`) |
| `{"cmd":"menuBarSelect","id":"^N#K"}` | a menu bar item through `performActionForItem(at:)` | `seq` |
| `{"cmd":"menuBarKey","char":"r","mods":["command"]}` | the key event offered to the main menu (`performKeyEquivalent(with:)`) | `seq`, `handled` |
| `{"cmd":"holdWorld"}` | from now on the host sends no clock of its own, arms no wake and runs no request: the driver sends both ("The world", below) | `seq` |
| `{"cmd":"clock","mono":m,"wall":w,"zone":z}` | `.clock` with that time | `seq` |
| `{"cmd":"reply","id":n,"reply":R}` | `.reply` to request `n` with `R`: `{"done":true}`, `{"bytes":HEX}`, `{"http":status,"headers":[[n,v]],"body":HEX}`, `{"failed":"timeout","message":…}`, `{"names":[…]}`, `{"app":pid,"name":…}`, `{"flag":b}` or `{"image":[w,h]}` | `seq` |
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

The socket changes four things about the app, and a fifth when the driver asks:

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
- **The world** (`holdWorld`, which the driver sends first). `Engine.holdClock`: no batch starts
  with the host's time and no wake is armed, so time moves only with the driver's `clock`
  events. `World.holdRequests`: no request is run, so no request reaches the network, the disk
  or another app, and every reply is the driver's `reply`. Each is an event with a seq, so `wait`
  covers it like input. Subscriptions still run.

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
- each control with a menu (docs/surfaces.md, "Menus on controls"): a secondary click, a click
  on a menu button, and the menu key (`Key.menu`) when it has focus;
- with a control's menu open, only what a person can do while AppKit tracks it: choose each item
  (an enabled one as a press of its move, a greyed one as plain UI, expecting nothing), or dismiss
  the menu;
- each item of the app's menu bar items (`Surface.menuBar`), enabled or greyed;
- plain UI: Tab, Shift-Tab, the pointer leaving the window, a hover anywhere, a click on empty
  space.

The walk picks a group uniformly, where a group is one control's trigger, one control's menu,
or plain UI. Editing the
focused field gets three times the weight. Then the walk picks a choice within the group.

The world's moves ("The world", below) are one more group, weighted by what is outstanding (one
per request and one for a timer, up to six), so replies come about as fast as requests.

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
  control's centre. A press on an item of a control's menu right-clicks the control and chooses
  the item; on a menu bar item, it chooses it. An edit focuses the field, then types, pastes or
  deletes. Submit is Enter.
- `--gestures FILE` re-models raw gesture lists. The driver uses it to shrink failures, and
  replays a file of them as extra sequences with `cairn conformance --gestures FILE`. The
  fixture's `conformance/menus.gestures` opens an item's menu with the menu key, Space, Return
  and a right click and chooses from it.

## The world

A running app hears more than a person: the time, and replies to its requests. Without a model
of them, the app's replies (and timers firing on the real clock) arrive between steps where the
model has none, and the walk fails at the next step. So the driver holds the world
(`holdWorld`), and the generator decides it, as `cairn fuzz`'s host does (docs/fuzz.md, "The
host" and "A server"):

- **Time.** Each sequence starts at `startTime` (mono 1000 ms): the driver sends it after the
  restart and the app boots on it, as the model does. When the model's frame has a `wake` (a
  timer is set), a world step moves the clock to it and the due timers fire in both.
- **Replies.** The generator keeps the requests the app sent and not yet answered, from the
  model's effects. A world step answers one, in any order: from the app's `Custom.server` if it
  takes the request, else from `Custom.replies`, else `failed other "conformance"`. With a
  server, its world is kept through the sequence (`Server.init` from the walk's seed), and a
  step can also fail a request before it reaches the server (the world unchanged) or lose its
  reply after (the world changed); both are the server's `fault`. A cancelled request is
  answered `failed other "cancelled"`, or with the server's reply if it had already handled it.
- **On the way.** `serve` (another request reaching the server, its reply held back) and `tick`
  (the server's world acting on its own) change only the server's world, so they happen on the
  way to a world step, at the server's `ticks` weight and one time in four.

Each world step is one gesture, `clock` or `reply`, which the driver sends and `--gestures`
lines carry (`clock MONO WALL ZONE`, `reply ID http STATUS BODY`, `reply ID failed FAULT
MESSAGE`, …; bytes in hex). A shrunk repro replays without the server: its replies are in the
lines. The results file counts world steps by kind (`world`: `answer`, `failedBefore`,
`lostAfter`, `wake`), and `report.md` lists them.

What the generator doesn't check: the server's claims (`Server.checks`); `cairn fuzz` checks
those against the same server, and conformance checks that the app does what the model does.

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
| menus | each status item's menu, the open control menu (`controlMenu`: owner and items) and the app's menu bar items (`menuBar`) equal the model's records, in `DebugJSON.menu`'s shape |
| model | the generator's findings are empty: every control on screen belongs to an enabled move (a menu button may belong to none: its ref names its menu), and a press delivered exactly that press (except a T33 dropped click, below) |

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
`report.md` lists them under "Known: open decisions", so the docs can say so.

## Results file

`build/conformance/<App>.json` uses the shape `tools/map/evidence.ts` reads:

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
naming the decision and the first walk and step. Places and assumptions aren't run; the docs show them as `n/a`. The extra fields (`sequences`,
`steps`, `probes`, `triggers`, `timing`, `plainUi`) are for people. `cairn doc` reads only `claims`.

## Shrinking

For the first failure of each kind, the driver shrinks the failing sequence:

1. It takes the shortest failing prefix.
2. It tries dropping each earlier step, last to first. A drop is kept if the sequence still fails
   anywhere.
3. Each candidate is re-modelled from its gestures alone (`--gestures`) and replayed on the app.

The repro in `report.md` is therefore re-verified on the app, one step per line, in the
generator's gesture format.

The runs below were on the examples while they were in this repository, with the Makefile's
`make conformance APP=<App>`. The apps are in cairn_examples now, where
`cairn conformance --app <App>` runs them; none of these runs is part of a `make check`.

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

Tray (`lean/Tray.lean` in cairn_examples) has no window: a status item with a native menu and an
overlay panel. The generator offers, for each shown status item:

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

## The fixture: menus on controls and the menu bar

The fixture (test/fixture) has an item menu on each item's ⋯ button and checkbox, and the app's
own Clear Done and Go menu. Opening a control's menu goes through the socket's `rightDown` and
`rightUp`, a click on the ⋯ button, or the `menu` key. The driver waits for the frame that opens
the menu before choosing from it, since the host builds the native menu from that frame.

Runs on a second Mac (macOS 26.5, Apple silicon, debug build):

- Before the Like buttons (#260, #261), `cairn conformance --n 1000 --length 20 --seed 3` passed
  1000/1000 walks and both flows, ^8 and ^33. ^33 finishes items from their menus and the app
  menu. The run covered 20,013 steps and 210,567 pixel probes. Runs per move, with the ids the
  moves have now:

  | Move | Runs |
  |---|---|
  | Mark Done from the menu (^26) | 3 in walks |
  | Delete (^27) | 5 in walks |
  | First Row (^31) | 1,507 |
  | No Row (^32) | 1,125 |

  A walk reaches an item's menu rarely, because it must add an item first. The flow and the
  gesture file cover the menu every run.
- With the Like buttons, `cairn conformance --n 0 --gestures conformance/menus.gestures` passes
  both gesture sequences and both flows (55 steps).
- With the Like buttons and the world modelled (#264), `cairn conformance --n 1000 --length 20
  --seed 3 --gestures conformance/menus.gestures` passed 1002/1002 sequences (the walks and the
  two gesture sequences) and both flows: 20,055 steps, 437,061 pixel probes, 171.6 s, per step
  p50 8.3 ms. Its world steps: 1,186 answers, 232 failed before, 216 lost after, and 112 clocks
  reaching a timer (the read-back backoff and Flash). Like (^21) ran 3,171 times and Refresh
  (^23) 783. The requests are answered by `cairn fuzz`'s fake server (Fixture/Fuzz.lean), so a
  lost reply is read back on the app as in the model.

  Before the world was modelled, walks failed at the first step after a Like or Refresh press:
  the requests went to `127.0.0.1:9`, and their failures came back as replies, with retries, that
  the model never saw. A run of that driver with every `HTTP 200` sent to the app as a 429 fails
  17 of 30 walks on `frame` and `ax`, shrunk to repros of four or five lines.

  The same run also fixed the generator's own check that a press delivers exactly that press: a
  press of End (^42) that scrolls the list's end line into view delivers `appear ^16` in the
  frame events after it, which the check now sets aside, as it does a `blur`.

Before this run the driver had not been run since secure fields (#217): it modelled neither the
`secure` flags nor `AXSecureTextField`, and failed every walk at its initial frame. Both are
modelled now.

## What it does not check

- **The window server.** Events are handed to the view, not routed by the window server or
  `NSWindow.sendEvent`. Window-level hit testing, key-window and first-responder routing, and
  `clickCount` timing aren't exercised; the socket sets `clickCount` itself.
- **Real input methods.** IME is driven through `NSTextInputClient` calls shaped like an input
  method's, not by a real Japanese or Chinese IME.
- **The user's key bindings.** Key equivalents go through `interpretKeyEvents` with the current
  user's key bindings. A custom `DefaultKeyBinding.dict` could change the results.
- **Popped-up menus.** A control's menu is built but never popped up under the socket, so where
  it appears, keyboard navigation inside it, and dismissal by a click outside are not exercised
  (docs/trusted.md, "Also trusted, not fuzzed").
- **Timing.** Every step waits for its frame, so coalescing and input racing ahead of frames are
  not exercised.
- **The real world.** Under `holdWorld` the host's request handlers, its clock and its wake
  timer don't run; the selftest, the trusted fuzz (`make fuzz-trusted`) and the host's tests cover
  them. Subscriptions (`every`, `watchFile`, …) still run on the real clock, unmodelled: an app
  with one would see events the model doesn't.
- **Things Basics and Counter lack.** Scrolling, live resize and window focus (`UI.windowFocused`) aren't
  exercised.
- **The compositor.** Pixels come from the presented drawable, not the screen.
