# test/fixture

Cairn's own app, for Cairn's own checks (#137). The framework's per-app checks (the headless
selftest, fuzzing, binary size, the input → frame bench, conformance) need an app to run on.
This is that app; the examples are in their own repository, iamnbutler/cairn_examples.

It is laid out as an app in its own repository is (`cairn new --bin`), and checked the way one
checks itself, with the `cairn` CLI (docs/cli.md, "Checks"). The only difference: it requires
this checkout by path, Lean (`require cairn from "../../../lean"`) and Swift
(`.package(path: "../..")`), so it tests the tree it is in.

What it covers, in one window (lean/Fixture.lean):

- layout: columns and rows, fill and fixed sizes, padding, gaps, clipping;
- text: a heading, a wrapped paragraph (`Node.para`), a text field with Enter, and a secure
  field (Passcode, `^9`) whose Enter sends it in a redacted request;
- hit testing: buttons, and keyed rows (`^4#k`, `^5#k`) that come and go;
- scroll boxes: a virtual list (place ^14) of 10,000 keyed rows (`^10#k`) of mixed height,
  whose offset the runtime owns, with Cairn's scroll-box and virtual-list theorems stated for it
  as claims ^12, ^13, ^20 and ^48 (lean/Checks/Scroll.lean; ^11, ^15 and ^19 are retired), buttons
  that add rows at the head and the tail (^17, ^18), an end line that hears `appear` (^16),
  buttons that scroll it with `scrollTo` (Top ^41, End ^42, Go to row ^43), and one that hides
  it and shows it again where it was (^44, `App.keepScroll`);
  `Fixture --scroll-shots <dir>` renders it offscreen at the top, scrolled and at the end;
- effects: Flash sets a timer, and the timer's message comes back through `receive`; Badge
  (^45) and Clear badge (^46) set the Dock badge, and Announce (^47) posts an accessibility
  announcement;
- a server: four Like buttons (`^21#k`) with their counts, toggles a server keeps, on Cairn's
  optimistic table (`Cairn.Optimistic`, Cairn's docs/optimistic.md; lean/Fixture/Like.lean):
  shown at once, written one at a time per post, rolled back in a line on refusal and read back
  when a reply is lost, with Refresh (^23) fetching each post's count. `cairn fuzz` checks ^22
  (a post at rest shows what the server holds) and ^24 (its count is the server's) against a
  fake server whose replies fail before it acts and are lost after, and whose other accounts
  like and unlike (lean/Fixture/Fuzz.lean); `lake exe likeMutant` checks that it catches a Like
  that takes a lost write for a refused one (lean/Fixture/LikeMutant.lean);
- menus (docs/surfaces.md): each item's ⋯ button (`^25#k`, a menu button) and its checkbox's
  secondary click open the item's menu, Mark Done (`^26#k`) and Delete (`^27#k`, greyed until the
  item is done); the app's own menus in the menu bar (^28): Clear Done (^29) in the app menu and a
  Go menu (^30) with First Row (⌘1, ^31) and No Row (⌘2, ^32, greyed and checked while no row is
  selected); flow ^33 finishes items from their menus; `conformance/menus.gestures` opens an item's
  menu every way for `cairn conformance --gestures`;
- claims: places, moves (press, edit, submit, keyed, emit), an invariant with a runnable check, a
  flow; its own scope `fixture` and its own claims.lock, so nothing here is in Cairn's ledger.

| Make target (Cairn's root) | What it runs here |
|---|---|
| `selftest` | `cairn build`, then `Fixture --selftest` (Sources/Fixture/main.swift) |
| `fuzz-quick` | `cairn fuzz --iterations 200 --out build/fuzz/quick` with `LEAN_ABORT_ON_NONLINEAR=1`, then `lake exe likeMutant` |
| `size` | `cairn size` |
| `fixture-ledger` | the ledger (scope `fixture`) and the axiom audit, rooted at `Checks` |
| `bench` | `cairn bench` (`Fixture --bench`), with Cairn's layout and render benches |

`cairn conformance` and `cairn doc` work here too; neither is in `make check` (conformance opens
the app's window).

Changing the fixture never moves a Cairn claim. Its own ids follow the usual rules all the same:
`cd lean && lake exe ledger update --scope fixture --root Checks --lock ../claims.lock`.
