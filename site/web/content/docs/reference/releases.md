---
title: Release notes and compatibility
nav: Release notes
eyebrow: Reference
lede: What changed in each version of Cairn, and what an app can rely on across versions.
---

An app depends on Cairn at a tag, `vX.Y.Z`, in both its lakefile and its `Package.swift`. One tag
pins the Lean package, the Swift library products and Cairn's claims. Release candidates are
tags too (`vX.Y.Z-rc.N`), which an app can pin while it tries a change, but only final versions
are published.

## What a version promises

- **Claims.** Cairn's `claims.lock` at the tag is its contract; [the id promise](#the-id-promise)
  below says exactly what that means.
- **The host protocol.** The frame format carries its own version.
- **The Lean API** has no stability promise before 1.0.
- **The toolchain.** An app uses the Lean toolchain in Cairn's `lean/lean-toolchain` at the tag
  (`v4.35.0` for every release so far), because Lake shares compiled modules only between
  identical toolchains.

## The id promise

A claim id is how everything else refers to a claim: an app's flows, its docs, an issue, a
review, another package. So an id is a promise about meaning, and the ledger (`lake exe ledger
check`, part of `make check`) enforces it on every change. Ids are scoped by package:
`cairn^212` and `yap^212` are different claims.

**What holds, from the release that issues an id onward:**

- **An id is issued once.** It is never renumbered, never reused for another claim, and never
  changes kind. `claims.lock` keeps one line per id ever issued and never removes one.
- **Its meaning doesn't change quietly.** The ledger hashes each claim's formal statement and the
  definitions it uses. A change to either, or to the title, is reported and has to be accepted
  with `lake exe ledger update --accept`, so it shows in review. Cairn's rule is that a new
  meaning gets a new id; acceptance is for a statement written differently that says the same.
- **It goes away only by retiring.** A retired id stays in the lock, with its kind, its title
  and the reason, and can't come back. Retiring a claim the last release had active needs a new
  major version, or a new minor version while at 0.x.
- **An id that leaves with an app stays issued.** It is marked `moved:<scope>` where it was, and
  lives on under the app's own scope.

**What can change in any release:**

- **How a claim is proved, and the code behind it.** Proofs, `apply`, and the names of bound
  variables aren't in the hash, so refactoring a handler doesn't touch its claim.
- **The prose.** `does` and `sees` can be reworded to say the same thing more clearly.
- **Its evidence.** What a claim reads as depends on the build that computed it. See
  [how much to trust a claim](/docs/reference/trust/).

## v0.5.0

26 October 2026.

A minor version, early in M5, for Sky's work on acting on Bluesky: optimistic values
(`Cairn.Optimistic`), a fuzz server with a world, menus on controls and in the menu bar,
`Effect.scrollTo`, kept scroll boxes, the Dock badge and announcements. No claim is retired or
moved, but `Surface`, `Key` and `Effect` gain constructors, the frame format goes to v13 and every
app links Lean's `libStd`, so apps need the changes under "Upgrading to v0.5.0" below.

- **Optimistic values: `Cairn.Optimistic`** (cairn#245). A `Table K V` holds values a person
  changes and a server keeps: a set shows in its own step, one write is in flight per key, a
  refusal rolls back in the step it arrives (said with `rolledBack`), and a lost reply is read
  back, never written again blind. Answers are matched by `Ticket` (key and request number), so
  stale ones are ignored, and views (`seen`) never move a key written this session. Counts over
  a boolean value: `count c v w`. Proved against a model server, for any order of replies, lost
  before or after the server acted: a settled key shows what the server holds, at most one write
  in flight per key, never more writes than sets, inputs for different keys commute, and counts
  are the server's and never below zero (`cairn^1100`–`cairn^1114`, docs/optimistic.md). The
  fixture's Like buttons now use it, with counts and Refresh (`fixture^23`, `fixture^24`).
- `bin/cairn-link` links Lean's `libStd` too, for `Cairn.Optimistic`'s `Std.TreeMap`; the
  linker takes only what an app reaches (the fixture is 3.33 MB stripped).
- **`cairn fuzz`: a server with a world** (cairn#246). `Custom.server` gives the fuzz host a
  `Cairn.Fuzz.Server`: a world that persists across a sequence, changed by the requests that
  reach it and by itself between steps, and checks over the app's state and the world, after
  every step (`server`) and once everything is answered (`serverDrained`). The host injects two
  faults the app can't tell apart: **failed before** (the world unchanged) and **lost after**
  (the world changed), and names each in the report. Replays and shrinking rebuild the world;
  the world is threaded without being copied. Theorems: each request is answered at most once,
  and a failed-before answer leaves the world as it was. The fixture's Like buttons (`fixture^21`,
  `fixture^22`) are checked against a fake server, and a mutant that takes a lost write for a
  refused one is caught (docs/fuzz.md, "A server").
- **`cairn fuzz`: per-move weights** (cairn#226). `Custom.weights s ref` weights a control's
  actions when the fuzzer picks one (default 1; 0 never picks it, and its presence is still
  checked).
- **Menus on controls** ([#247](https://github.com/iamnbutler/cairn/issues/247)).
  `Style.menu := some { items, button }` puts a native menu on a control. The menu is a context
  menu, or with `button := true` a menu button (⋯).
  - What opens it: a secondary click, the context-menu key (`Key.menu`: Shift-F10 or the PC Menu
    key) on the focused control, VoiceOver's Show Menu, and for a menu button a click, Space or
    Return.
  - Lean keeps the open menu in `UI.menu`. Opening it reaches no `update`.
  - Choosing an item is a press of that item's control, checked against the open menu: a greyed
    or stale choice does nothing.
  - The host pops up an `NSMenu` built from the window record's `status`, and sends `menuClose`
    when the menu returns. A menu button is an `AXMenuButton`.
  - Theorems: `Runtime.secondary_opens`, `menu_open_presses`, `menu_select_presses`,
    `menu_select_stale`, `menu_select_absent`, `step_open_quiet`.
  - See docs/surfaces.md, "Menus on controls".
- **The app's own menus in the menu bar** ([#229](https://github.com/iamnbutler/cairn/issues/229)).
  `Surface.menuBar place view` adds the app's own items to the main menu:
  - Top-level submenus become menus before Window (Go, View).
  - Other entries go at the top of the app menu, above Hide and Quit (Sign Out).
  - An item's shortcut is its key equivalent whenever the app is active (Refresh ⌘R).
  - See docs/surfaces.md, "The app's menus".
- **Six new `assume` claims, fuzzed by the trusted fuzzer's new `menus` suite:** ^945–^948 for
  control menus (render, select, dismiss, `AXShowMenu`) and ^949–^950 for the menu bar (render,
  select by click and by key equivalent). Three findings, now fixed in the host:
  - A shifted letter's key equivalent must be the capital, or ⇧⌘A never matches. This applies
    to status item menus too.
  - The main menu auto-enabled greyed items, so their key equivalents pressed them.
    `MenuHost.validateMenuItem` now answers with the record's own flag.
  - See docs/trusted.md.
- **Frames v13.** The format adds:
  - the `menuBar` surface kind (3);
  - the window's open control menu, in its `status`;
  - an ax record's `menu` byte;
  - key code 14 (`menu`).

  Events stay at v2. An app and its host must use the same Cairn tag, as always.
- **Breaking for exhaustive matches.** `Surface` has a new `menuBar` case and `Key` a new `menu`
  case. `Shortcut` and `MenuItem` moved from `Cairn/Surface.lean` to `Cairn/UI/Node.lean`; they
  keep their names.
- **Conformance.**
  - New gestures: secondary clicks, a control's menu (chosen through `performActionForItem(at:)`
    or dismissed), and the menu bar's items. Each step compares the open menu and the menu bar
    with the model.
  - `cairn conformance --gestures FILE` replays extra gesture sequences.
  - The driver now models secure fields. It had failed every walk since #217.
- **`cairn fuzz`:**
  - It presses control-menu and menu bar items as the host does.
  - Its presence check counts menu items whether or not the menu is open.
  - A new check, `menu-greyed`, chooses greyed items and expects nothing.
- **The fixture** gains an item menu (⋯ and the checkbox's secondary click; `fixture^25`–^27),
  Clear Done and a Go menu in the menu bar (^28–^32), and flow ^33. The statements of `fixture^12`,
  ^13 and ^48 quantify over the fixture's view, which changed, and were accepted.
- `Cairn.Fuzz.Custom` is in `Type 1` now (it can hold a server's world type); `World` and
  `Performed` take the world's type.
- **`Effect.scrollTo`** (cairn#234). An app moves a scroll box or a virtual list: `scrollTo ref
  .start`, `.finish` or `.key k` (the row keyed `k` at the top of the box). The runtime runs it
  after layout, lays out again until the offset settles, and clamps it like every offset; the
  list's anchor then keeps that row still. Theorems: `aimOff_start`, `aimOff_finish`,
  `aimOff_key`, `firstF_top`; `step_clamped` holds with it. `cairn fuzz` checks it lands
  (`scrollTo`). Frame format version 12 (effect tag 8).
- **Kept scroll boxes.** `App.keepScroll` names boxes whose offsets, and for virtual lists whose
  heights and anchor, survive while they are out of the view; shown again, they come back where
  they were (`fixUI_keeps_offset`, `fixUI_keeps_list`, `fixUI_revives`; fuzzed as `kept`).
- **The Dock badge and announcements** (cairn#248). `Effect.badge (label : Option String)` sets
  the Dock tile's badge (`none` clears it), and `Effect.announce text priority` posts an
  accessibility announcement. Each is one AppKit call (`Notices`). Two new `assume` claims, each
  fuzzed by the trusted fuzzer's new `notices` suite: ^1030 (`hostBadge`, `dock.badge`), the
  badge is the last `badge` effect's label or none, and ^1031 (`hostAnnounce`, `ax.announce`),
  an announcement is posted once with exactly its text. The fuzz host records both
  (`Custom.badge` checks the badge), and announcement text goes through the secure-field check
  like every effect. Effect tags 9 and 10.
- **The fixture** gains Top, End, Go to row and Hide rows (`fixture^41`–`^44`), Badge, Clear
  badge and Announce (`fixture^45`–`^47`). `fixture^19` is retired for `fixture^48`, which states
  the rows' stacking while they are shown.

**Claims.** 23 are new and none is retired, moved or changed: `assume` ^945–^950 (control menus
and the menu bar), ^1030 and ^1031 (the badge and announcements), and `Cairn.Optimistic`'s seven
moves and eight invariants, ^1100–^1114. The test fixture (scope `fixture`, unpublished) adds
^21–^33 and ^41–^48, retires ^19, and accepted new statements for ^2, ^3, ^12, ^13 and ^20.

### Upgrading to v0.5.0

Change the tag in the lakefile and `Package.swift` (an app and its host must use the same tag:
frames are v13), then:

- **Linking.** Every app links Lean's `libStd` as well as `libCairn` (cairn#261). `bin/cairn-link`
  and `cairn build` do it; an app with its own link step adds `-lStd` from the toolchain's
  `lib/lean`.
- **New constructors.** Exhaustive matches on `Surface` need a `menuBar` case, on `Key` a `menu`
  case, and on `Effect` `scrollTo`, `badge` and `announce` cases.
- **Moved types.** `Shortcut` and `MenuItem` are in `Cairn/UI/Node.lean` (still `Cairn.Shortcut`
  and `Cairn.MenuItem`); code that imported `Cairn.Surface` only for them imports `Cairn.UI.Node`.
- **New fields**, all defaulted: `Style.menu`, `UI.menu`, `UI.kept`, `UI.keptLists`,
  `App.keepScroll`, and `Custom`'s `weights`, `server` and `badge`. Named-field construction
  needs nothing; positional construction needs the new ones.
- **Fuzzing.** `Cairn.Fuzz.Custom` is in `Type 1`, and `World` and `Performed` take the server
  world's type as a second argument (`World S W`). Code that only builds a `Custom` with named
  fields is unaffected.

## v0.4.1

26 October 2026, at commit `a6a35fb`.

- **Keychain calls no longer deadlock** ([#237](https://github.com/iamnbutler/cairn/issues/237)).
  A `forgetSecret` racing a read of the same app's items (a request's Keychain secret, a
  capture, or Sky's selftest listing its items) could hang both forever inside Security's
  file-based keychain. `KeychainStore` now makes every Security call on one serial queue for the
  whole process; code outside it that calls Security on the same keychain can join the queue
  with `KeychainStore.serialized { … }`. Requests in flight at once still reach the Keychain in
  no promised order. The trusted fuzzer's `effects.secret.keychain` gains a live concurrency
  check (`keychain.concurrent`), skipped under `CI` like the rest of the live part. See
  docs/effects.md and docs/trusted.md (^972).
- **A Keychain value keeps a leading byte order mark.** `KeychainStore.read` decoded with
  `String(data:encoding:)`, which drops one, so a value starting with U+FEFF read back without
  it; it now decodes with `String(validating:as:)`. Found by the full trusted fuzz run.
- **The accessibility mirror's M4 assumptions are claims, fuzzed.** Two new `assume` claims
  replace what was reviewed by hand: ^1021 (`hostAxScroll`), assistive apps reach only what a
  scroll area shows, and ^1022 (`hostAxSecure`), a secure field shows them nothing typed and the
  debug socket's request log shows no secret. The trusted fuzzer's new `ax` suite checks both
  (`ax.scroll`, `ax.secure`) on a real `HostView` through AppKit's accessibility API.
  docs/trusted.md gains a table of every assumption M4 added and its fuzz check.

Two claims are new (^1021, ^1022); none was retired, moved or changed, so it is a patch release.
Moving from v0.4.0 is a change of tag in the lakefile and `Package.swift`.

## v0.4.0

25 October 2026, at commit `f107007`.

A minor version: the runtime takes over scroll offsets, reports controls coming on screen and
lays out virtual lists, and fuzz targets are scoped by package. Only one claim is added, but
`Event`, `Action` and `Trigger` gain constructors and `Style` and `UI` gain fields, so apps may
need the changes under "Upgrading to v0.4.0" below. The frame format is unchanged (frames 11,
events 2).

- **Scroll offsets belong to the runtime** ([#203](https://github.com/iamnbutler/cairn/issues/203)).
  A scroll box names itself with `Style.scrollRef`, and the runtime keeps its offset in
  `UI.scroll`, keyed by that ref; the view reads it with `ui.scrollOf ref`, or `ui.scrolling ref
  style`. The wheel and trackpad move the innermost box under the pointer; Page Up/Down,
  space/shift-space, Home/End and the arrows move the focused control's box or the one under the
  pointer; Tab scrolls the control it focuses into view. Every offset is clamped to `[0, max 0
  (content − viewport)]` after every step (`Runtime.step_clamped`), and a scroll never reaches
  `update` (`Runtime.step_scroll`). The host's scroll sign is a claim (^1012, below). See
  docs/runtime.md, "Scrolling".
- **`Action.appear`.** A control with `Control.appear := true` is reported to its move when it
  comes on screen: after each batch, `Runtime.steps` runs `Runtime.frameEvents` (two
  `Event.frame`s), which deliver `appear c` for each such control that has a visible part and
  didn't at the last frame (`Runtime.appear_iff`). Moves answer it with `on appear`.
  `Event.frame` is the runtime's own and has no wire encoding.
- **Virtual lists** ([#204](https://github.com/iamnbutler/cairn/issues/204)). `VList.node`
  lays out only the rows of a list that meet its box, widened by an overscan, between two
  spacers, whatever the list's length: a runtime step costs about 0.17 ms at 1,000 rows and at
  100,000 (bench/vlist.md). Rows are estimated until laid; the runtime records the heights it
  lays them at in `UI.lists` and keeps the first row showing still when rows are inserted or
  heights change above it. `Style` gains `rows`, and `Runtime.settleFuel` goes from 2 to 4, so
  the frame shown is laid at the heights just recorded. Theorems: the rows built are exactly those
  meeting the widened box and no more than it can hold (`VList.node_rows`), one under the other
  with no gaps (`Layout.vlist_stacked`), and the offset correction keeps the anchor still unless
  clamped (`VList.record_keeps`). See docs/layout.md and docs/runtime.md, "Virtual lists".
- **Fuzz targets are scoped by package** ([#221](https://github.com/iamnbutler/cairn/issues/221)).
  `fuzz_targets%` marks a machine from a dependency (cairn_atproto's session, in an app that
  requires it) and names it with its package first, `cairn_atproto/Claims`, so it no longer
  shares the app's `Claims` and shadows it. `lake exe fuzz --list` and `cairn fuzz` run only the
  package's own machines; `--deps` adds the dependencies', and any target can be named. Two
  targets with one name fail to compile, naming both, and `Cairn.Fuzz.main` refuses a list with
  a name twice. `Target` gains `package` and `dependency`, and the report gains `package`.
- **`cairn fuzz` scrolls and checks virtual lists.** It sends wheel ticks and flicks at random
  points, far past either end, and the scroll keys; after every step it checks every box's
  offset against the clamp and each list's window against the specification, its stacking, that
  its rows were laid at their recorded heights, and that the first row showing stays still over
  operations that don't scroll. It counts `appear` moves under their claims, and for controls
  keyed by their row, presence is "enabled and its row is laid".

**Claims.** New `assume` ^1012 (`hostScroll`): the host reports a positive `dy` toward the end
of the content, 16 points a wheel line, fractions carried; fuzzed as `pointer.scroll`. Nothing is
retired or moved. The test fixture (scope `fixture`, unpublished) retires ^11 for ^15 and adds
^14 and ^16; its scroll box becomes a virtual list of 10,000 rows of mixed height, ^15 is retired
for ^19 and ^20 (the rows stacked, and which rows are built), and ^17 and ^18 add rows at the
head and the tail.

### Upgrading to v0.4.0

Change the tag in the lakefile and `Package.swift`, then:

- **New constructors.** Exhaustive matches on `Event` need a `frame` case, on `Action` an
  `appear` case, and on `Trigger` an `appear` case.
- **New fields.** `Style` gains `scrollRef` and `rows`, and `UI` gains `scroll` and `lists`, all
  defaulted. Code that builds a `Style` or a `UI` with named fields needs nothing; code that
  lists every field positionally needs the new ones.
- **Scroll boxes.** A view that scrolled a box by an offset in its own state should name the box
  (`ui.scrolling ref style`) and drop the offset; an offset of its own still works, unclamped and
  unmoved by the runtime.
- **Hand-rolled batches.** Code that folds `Runtime.step` over a batch to mirror `Runtime.steps`
  should append `Runtime.frameEvents`. Code that calls `Runtime.settle` itself should pass
  `Runtime.settleFuel` (now 4) rather than a literal.
- **Fuzzing.** `cairn fuzz` and `lake exe fuzz --list` no longer run a dependency's machines;
  add `--deps` to include them, or name a target (`cairn_atproto/Claims`). An app that filtered
  `fuzz_targets%` to its own modules can drop the filter.

## v0.3.0

25 October 2026, at commit `60c4483`.

A minor version: it moves the example apps' claims out of Cairn, retires claims, removes
modules and changes the frame format, so apps need the changes under "Upgrading to v0.3.0"
below.

- **The example apps are out of Cairn** ([#137](https://github.com/iamnbutler/cairn/issues/137)).
  Counter, Basics, Todo, Clock, Tray and Gallery are in their own package,
  [`cairn_examples`](/packages/cairn_examples/), which requires Cairn from the registry like any
  app. Their 71 claims keep their numbers and statements there and are `moved:cairn_examples` in
  Cairn's `claims.lock` (^1–^5, ^101–^109, ^201–^226 but for ^213–^215 and ^225, ^401–^409,
  ^450–^462, ^501–^513): `cairn^202` is now `cairn_examples^202`. ^6, ^213, ^215 and ^225 stay
  retired, and ^7 and ^214 stay in Cairn's trusted base, so Cairn's ledger now holds only
  framework claims. `lean/Examples`, the `Examples` Lake library, the host's `Cairn<App>`
  executables, the `/try/` pages and the Makefile's `demo`, `bundle`, `capture`,
  `conformance`, `fuzz`, `doc APP=` and `examples-*` targets are gone; the per-app checks run
  on test/fixture with the `cairn` CLI. `CLean`'s header no longer declares the examples'
  initializers.
- **Secrets in the Keychain** ([#205](https://github.com/iamnbutler/cairn/issues/205)). A
  `Secret` now has a `source`: `.env file name` (what `Secret` was before) or `.keychain
  account`, a generic password item under the app's bundle identifier. `Request.http` gains
  `secret` and `capture`: a 2xx JSON object reply's listed top-level string fields are written
  to Keychain items and blanked before Lean sees the body. `Request.forgetSecret account`
  deletes an item. A request carrying a secret no longer follows redirects.
- **Secure text fields** ([#206](https://github.com/iamnbutler/cairn/issues/206)).
  `Text.SecureField` wraps a field: its view shows one bullet per scalar
  (`FieldView.secure := true`), copy and cut beep and never set the clipboard, and it keeps no
  undo history (proved in `Cairn.Text.Proofs`). The host gives it the `AXSecureTextField` role
  with no value and turns on secure event input while it has focus. `Request.http` gains
  `redact`: a redacted request dumps as `<redacted N bytes>` in `Frame.Dump`, the debug socket
  and fuzz output, and a dump of a frame holds none of a secure field's text (`secure_frame` in
  `Cairn.Frame.Dump`). The fuzzer plants text in secure fields and fails if it appears in any
  dump.
- **Scroll boxes** ([#202](https://github.com/iamnbutler/cairn/issues/202)). `Style.scroll :
  Option Int`: `some o` lays a box's children out as its axis says, moves them back by `o` and
  clips them. `Pressable`, `layout_good` and `hitTest_center_of_pressable` now speak of a
  control's visible part (`rect ∩ clip`); without scroll boxes it is the whole rect
  (`visible_eq_rect`, `hitTest_center_of_fitsIn_flat`). `Cairn.Layout.Scroll` proves, for every
  scroll box, that its children are the unscrolled ones moved back by the offset, that they stay
  apart and show only inside the box, and that a control is pressed at the centre of what shows
  of it and nowhere if nothing does. The frame draws only a scroll box's visible children and
  gives it an accessibility node of role `scrollArea`; the host's mirror leaves out what is
  scrolled away. The test fixture has a scroll box of 200 rows (`fixture^10`–`^13`).
- **Frame format version 11** (`docs/frame.md`). It adds the Keychain secret source
  (`[2, 0, 0, 0]`), `http`'s secret, captures and redact flag, the `forgetSecret` request
  (kind 17), the `secure` flag on accessibility and text-input records, and the `scrollArea`
  role (10). A host and a Lean library must both be at 11. Versions 9 and 10 were steps on main
  and never shipped in a release. An `upload` with no secret or an environment secret is
  encoded as before.
- **The 0.1.3 shims are gone.** `Cairn.Frame.Boundary`, `Cairn.Runtime.Hit` and
  `Cairn.Text.Metrics` no longer exist; import `Cairn.Abi`, `Cairn.UI.Hit` and `Cairn.Font`.

**Claims.** 71 ids moved to `cairn_examples` (above). ^913 and ^971 are retired and reissued
as ^974 and ^975, now that a secret can come from the Keychain. New `assume` claims: ^972 (the
Keychain store), ^973 (captured reply fields) and ^1020 (secure event input). The Todo
example's ^225 is retired as ^226, which moved with Todo. The ledger counts a move like a
retirement (`Cairn.Claims.LedgerTests`), which is why this is a minor version.

### Upgrading to v0.3.0

Change the tag in the lakefile and `Package.swift`, then:

- **Environment secrets name their source.** Write `{ header, scheme, source := .env file name }`
  (Yap's `apiKey`; its `upload` is otherwise unchanged).
- **`http` patterns take eight arguments.** `secret`, `capture` and `redact` are defaulted, so
  `.http m u hs body t` still builds the same request, but a pattern that lists five
  (`| .http m u hs b t =>`) now matches only requests with no secret, no captures and no
  redaction. Write `| .http m u hs b t _ _ _ =>` or `| .http m u ..`. Exhaustive matches on
  `Request` need a `forgetSecret` case, and on `Role` a `scrollArea` case.
- **Shim imports.** Replace an import of a removed shim with its module: Yap's
  `Cairn.Frame.Boundary` is `Cairn.Abi`.
- **Example claims.** An app that cited a Cairn example claim (`cairn^202`) cites
  `cairn_examples^202`.
- **Hit testing.** `hitTest_center_of_fitsIn` takes `t.visible.nonempty`; use
  `hitTest_center_of_fitsIn_flat` with `(n.scrolls = false)` for the old statement.

## v0.2.5

25 October 2026, at commit `ea05c5e`.

- **Closing the window quits the app cleanly.** The window delegate now owns the window
  (`isReleasedWhenClosed = false`), and on close it shuts the view down (engine, `World`,
  render loop, observers) before the app terminates. Before, AppKit also released the window on
  close, and a frame that landed afterwards reached the freed window: Pairs 0.1.2 crashed in
  `objc_retain` when its window closed. `make selftest` closes a real window with input, a timer
  and frames in flight (`Fixture --close-test`). See `docs/host.md`.
- **`cairn` builds fetch registry dependencies quickly.** Before each Lake run, `cairn`
  fetches the commit the manifest pins for each registry dependency, and turns Lake's lazy
  fetches off when every git dependency is on a registry (#196). A stale checkout went from
  92 s to 4 s on Pairs. See `docs/cli.md`.
- **The tray's tick-rate selftest** checks Lean's per-tick cost against the 20 ms period and
  the timer's own ticks; the wall-clock rate is asserted on real hardware only, not on CI VMs.

No claim was retired, moved or changed, and none is new: `claims.lock` is the same as v0.2.4's,
so it is a patch release. Moving from v0.2.4 is a change of tag in the lakefile and
`Package.swift`.

## v0.2.4

25 October 2026, at commit `654c669`.

- **The fuzzer plays the host.** `cairn fuzz` answers the requests an app's frames make (late,
  in any order, one in six failed), replies to cancelled ones, fires timers at the frame's
  `wake`, moves the clock, sends subscription events and evicts images under an
  `imageCache`'s budget, all within what the trusted claims allow (^908, ^909, ^914, ^915,
  ^1006, ^1009, ^1011). A seed replays its host moves exactly. A new check runs after every
  step: every image the frame draws is one the host holds.
- **`Custom` takes more of an app.** `replies` and `subEvents` generate the replies and
  subscription events an app expects; `relations` checks claims stated about every step as
  relations over a transition; `drained` checks a state after the host has answered everything
  outstanding; and `outstanding` checks the app's bookkeeping, after every step, against the
  ids of the requests the runtime still holds for it. See `docs/fuzz.md`.

No claim was retired, moved or changed, and none is new: `claims.lock` is the same as v0.2.3's,
so it is a patch release. Moving from v0.2.3 is a change of tag in the lakefile and
`Package.swift`.

## v0.2.3

25 October 2026, at commit `8ecf96e`.

- **Several apps in one package.** Each `lean_lib` in `libs` whose library defines
  `cairn_app_init` is an app, and `cairn build`, `size`, `bench` and `conformance` take
  `--app <Lib>` to link one (it defaults to the only app). With several, each app's archive is
  `.cairn/lib/lib<name>_<app>.a`. `cairn claims --ledger`, `publish` and `doc` still read every
  lib. The example apps are also in iamnbutler/cairn_examples, which is such a package.
- **`cairn bundle`.** A release build of an app package wrapped in `build/apps/<N>.app`, with the
  SwiftPM resource bundles its executable uses copied into `Contents/Resources`, where
  `Bundle.module` looks in an app. The package's `bundle/Info.plist` and
  `bundle/entitlements.plist` are used when present; it signs with `--sign`, else ad hoc.
- **The fuzzer sees more of an app.** A status item's button and menu items count as on screen,
  and the fuzzer presses them with `menuOpen` and `menuSelect`, so Clock and Tray are fuzzed. It
  takes `App.minSize` as the window's minimum, since the host never makes the window smaller
  (`cairn^1010`), so Gallery is fuzzed too.
- **Clicks are in the trusted base.** `cairn^7` (a click reaches Lean where it happens) and
  `cairn^214` (a double click is a second click) were declared by the Counter and TodoMVC
  examples. They now live in `Cairn.Fuzz.Trusted.Claims`, with the same ids and statements,
  and the trusted-base fuzzer checks them (`pointer.click`, `pointer.double-click`).

No claim was retired, moved or changed, and none is new: `claims.lock` is the same as v0.2.2's,
so it is a patch release. Moving from v0.2.2 is a change of tag in the lakefile and
`Package.swift`.

## v0.2.2

25 October 2026, at commit `885b585`.

- **A window's minimum size.** An app declares its window's smallest content size with
  `App.minSize`, and the host keeps the window at least that big (the trusted claim
  `cairn^1010`). `Cairn.UI.Grid.minBox n cols` is the smallest box in which a grid has `cols`
  columns and every card is at least `minWidth` wide, proved for every card and column count:
  at any size from it up, no card is narrower, and no smaller box does it. Gallery's window is at
  least 1020 × 536, three columns of 180-point tiles (`cairn^511`). The frame format is version
  7: the surface record holds the minimum size.
- **A budget on the host's images.** An app that subscribes to `Sub.imageCache bytes` has the
  host keep its decoded images within `bytes`, dropping the ones used least recently, never one
  the latest frame draws, and sending `SubEvent.evicted source` for each after it is gone (the
  trusted claim `cairn^1011`). `Cairn.UI.Images.evicted` sets the image back to loading and
  forgets any load of it in flight, and `Images.Cache` proves that an image the table takes for
  ready is held by the host or has a notice on its way. Gallery pages 24 thumbnails under an
  8 MiB budget (`cairn^512`, `cairn^513`). The frame format is version 8: `imageCache` is
  subscription 4, and `evicted` is subscription event 8.

No claim was retired, moved or changed, so it is a patch release. Five claims are new:
`cairn^511`–`cairn^513` (Gallery), `cairn^1010` and `cairn^1011`. Moving from v0.2.1 is a change
of tag in the lakefile and `Package.swift`, unless an app builds frames by hand, which are now
version 8.

## v0.2.1

25 October 2026, at commit `d08381d`.

- **Requests in flight.** At most `App.maxInFlight` (6) `http`, `upload` and `loadImage`
  requests are with the host at once; the rest queue in order. The new `cancelRequest` effect
  drops a queued request, or cancels a sent one, whose single answer then reaches no app.
  `Cairn.Runtime.InFlight` proves the cap is never exceeded, every queued request is eventually
  sent or cancelled, and a cancelled id never delivers. `Cairn.UI.Images` has `cancel`,
  `cancelAll` and `cancelWhere`. The frame format is version 6: `cancelRequest` is effect 7. The
  host's side is the trusted claim `cairn^1009`.
- **A grid that follows the window.** `Cairn.UI.Grid` lays out equal cards in as many columns of
  `minWidth` as fit the box's width, at least one, and shrinks them together when the rows would
  be too tall. It is proved for every size and card count: the cells stay inside the box, keep
  reading order and never overlap. The Gallery example uses it (`cairn^509`, `cairn^510`).
- **More of the `cairn` tool.** `cairn fuzz`, `claims`, `bench`, `size` and `conformance` run
  the per-app tools on any app package, as `cairn build` does. `test/fixture` is Cairn's own
  fixture app, with its own scope and ledger, and `make check` runs against it.
- **Claim pages.** `cairn publish` also sends the claims export (`cairn claims --ledger`) when the
  registry takes one, and the site renders every package's claims grouped by place, with a page
  per claim. The maps (`/map/<app>/`) redirect to them.

No claim was retired, moved or changed, so it is a patch release. Six claims are new:
`cairn^506`–`cairn^510` (Gallery) and `cairn^1009`. Moving from v0.2.0 is a change of tag in the
lakefile and `Package.swift`, unless an app builds frames by hand, which are now version 6.

## v0.2.0

24 October 2026, at commit `16b70b8`.

- **Images.** `Node.image` shows a picture in a fixed box whose size layout knows before any
  pixels arrive, and the `loadImage` effect asks the host for one, from a file or an `http`/`https`
  URL. The host decodes and paints; Lean never holds pixels. `Cairn.UI.Images` is the table an app
  keeps, and only the reply to a source's latest load counts. The frame format is version 5: an
  `image` draw and the `loadImage` request. Three trusted claims cover the host's side
  (`cairn^1006`–`cairn^1008`), and the Gallery example (`swift run CairnGallery`) shows six tiles
  with Reload and Fit. See [Effects](/docs/guide/effects/).
- **`import Cairn` links.** The `Cairn` module now imports exactly the `Cairn` library, what
  `bin/cairn-link` links, and `meta`-imports the claim commands, so an app can start with
  `public import Cairn`. The old umbrella that imported everything, proofs and tools included, is
  `CairnAll`; the ledger and the audit read it. An app that imports it doesn't link.
- **`cairn new --bin` makes a working app**: a window with a count and a Count button, its
  exports, a `Package.swift` and a host with `--selftest`. `cairn build` finds a Cairn required by
  path.
- **cairn-link links each dependency's `libs`** from its `cairn.toml`, rather than Cairn's library
  by name, so a library such as `cairn_json` is linked by naming its own. Cairn's `cairn.toml`
  says `libs = ["Cairn"]`.

- **`cairn^213` is retired and reissued as `cairn^225`**, with the same meaning: the TodoMVC
  example's rows are the todos the filter accepts. Its statement hash changed when `Style` gained
  its image field, and the registry keeps a published claim's statement, so the claim needed a new
  id. Retiring a released claim needs a new minor version while at 0.x, so this is 0.2.0 and not
  0.1.4. The tag `v0.1.4` exists, but the registry refused it for this reason and it was never
  published; use `v0.2.0`.

Eight claims are new besides `cairn^225`: `cairn^501`–`cairn^505` (Gallery) and
`cairn^1006`–`cairn^1008`. The shims from v0.1.3 are still there. Moving from v0.1.3 is a change
of tag in the lakefile and `Package.swift`, unless an app imports `Cairn` for the proofs or
tools, which are now in `CairnAll`, builds frames by hand, which are now version 5, or cites
`cairn^213`.

## v0.1.3

24 October 2026, at commit `aea142c`.

- **Three modules moved, with shims.** `Cairn.Frame.Boundary` is now `Cairn.Abi`,
  `Cairn.Runtime.Hit` is `Cairn.UI.Hit` and `Cairn.Text.Metrics` is `Cairn.Font`. The old names
  still work: each is a one-line module that imports the new one, until 0.2.0. `make lint` now
  fails on any cycle between directories in `lean/`, and there are none.
- **The `Cairn` library is only what apps link.** It holds the 31 modules `bin/cairn-link`
  archives into an app. Proofs, claims, fuzzing and tools are their own Lake libraries:
  `CairnProofs`, `CairnClaims`, `CairnFuzz` (was `Fuzz`), `CairnTools`, and `CairnTrusted` (was
  `TrustedClaims`). `libcairn_Cairn.a` goes from 3.67 to 2.78 MB and `libcairn_lean.a` from
  20.84 to 19.94 MB. The host now initializes Lean through `initialize_cairn_Cairn_Abi`.
- **One public registry.** The `cairn` tool uses `https://cairn.registry.nexthub.sh` by default
  (`CAIRN_REGISTRY` overrides it). `add`, `build` and `doc` need no login, and `cairn login` is
  needed only to publish. `cairn publish` publishes under `--owner`, or the token's own login.
- **Owners by name.** `cairn add <name>` finds a package's owner with
  `GET /api/v1/names/<name>`, not a search. `cairn publish` sends `swift`, whether the tag has a
  `Package.swift`, and a package page shows the `.package(url:)` line only when it does.

No claim was retired or changed. Moving from v0.1.2 is a change of tag in the lakefile and
`Package.swift`, unless an app names the `Fuzz` or `TrustedClaims` libraries, which are now
`CairnFuzz` and `CairnTrusted`. Yap moved with only its tag changed.

## v0.1.2

24 October 2026, at commit `597dea8`.

- **Libraries and apps.** `cairn.toml` has a `kind`: `"lib"`, which other packages can depend
  on, or `"bin"`, an app, which nothing can. It defaults to `"lib"`, and Cairn is one.
  `cairn new --lib` or `--bin` picks it, and `cairn new` asks with neither. `cairn publish`
  sends it, and `/packages/` lists apps under their own tab.
- **No uploaded docs.** `cairn publish` no longer runs `cairn doc` or sends docs, and
  `--no-docs` is gone. HTML from a publisher would run as the registry's site, so a registry
  will build docs from the source instead, as docs.rs does.
- **Retiring a claim needs a major version.** `lake exe ledger check` and `update` compare
  `claims.lock` with the last release's, found from the highest final `v<version>` tag that
  isn't after `cairn.toml`'s version. A claim that release had active can be retired, or moved,
  only in a new major version, or a new minor one while at 0.x. See
  [`retire`](/docs/reference/claims/#retire).

No claim was retired or changed, and the Swift libraries are the same, so moving from v0.1.1 is
a change of tag in the lakefile and `Package.swift`. An app that uses `cairn new` or
`cairn publish` needs the `cairn` tool from this tag.

## v0.1.1

24 October 2026, at commit `ea72e75`.

- **`cairn doc` works in an app's own repository.** In v0.1.0 it read its stylesheet and icon
  from the package it was documenting rather than from its own checkout of Cairn, so it failed
  for every package but Cairn itself.
- **The `cairn` command** is in this release, in `tools/cairn`: `new`, `add`, `build`, `doc`,
  `publish` and `login`. See [the cairn tool](/docs/reference/cairn-tool/).

Nothing in the Lean package, the Swift libraries or `claims.lock` changed, so moving from v0.1.0
is a change of tag in the lakefile and `Package.swift`, and nothing else.

## v0.1.0

24 October 2026, at commit `13ddd6c`. The first release.

- **Cairn is a package.** An app in its own repository requires the Lean package from git with
  the tag and the `lean` subdirectory, and the Swift package at the same version. The root
  `Package.swift` has library products only (`CLean`, `CairnFrame`, `CairnRender`, `CairnHost`
  and `CairnCapture`). None of them use `unsafeFlags`, which SwiftPM refuses in a dependency, and
  none of them link Lean. Lean's C header is committed, so a checkout builds without a
  toolchain step.
- **One link step.** `bin/cairn-link` merges Lean's runtime, Cairn's Lean library and the app's
  own into one static library for the host, and refuses a result with two `cairn_app_init`s.
  An app runs it from its Lake checkout of Cairn, and Cairn's own build uses it too.
- **Claim ids are scoped by package.** Cairn's are `cairn^N`. An app sets its own scope in its
  lakefile, and its ids are then `yap^311` and so on. See
  [Scopes](/docs/reference/claims/#scopes).
- **Yap moved out** to its own repository, `yap-cairn`, the first app to depend on Cairn this
  way. Its Lean, proofs, fuzzers, Swift host and benches left with it. Cairn's `claims.lock`
  marks its 44 ids `moved:yap`, so they stay issued and can't come back.

At this tag Cairn's `claims.lock` lists 146 ids: 100 active, 2 retired and 44 moved to Yap.
