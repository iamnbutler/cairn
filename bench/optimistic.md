# Optimistic values

Two benches for M5's acting half on Cairn's side (cairn#256): the optimistic table itself
(`Cairn.Optimistic`) at up to 1,000,000 keys, and a press → frame on the fixture's Like buttons,
which sit on that table. Sky's half (press → confirmed, mute → frame, notifications' first page,
flings with the new buttons, memory) is in Sky's `bench/`.

## The table: `bench --optimistic`

`cd lean && lake build bench && LEAN_ABORT_ON_NONLINEAR=1 .lake/build/bin/bench --optimistic
[N…]` (also run by `make bench`; the default sizes are 100, 10,000 and 1,000,000). For each
size `n`:

- **build**: an empty `Table K Bool` fed `seen k false` for every key, in order, so it holds `n`
  entries (`Std.TreeMap`).
- Then 20,000 inputs of each kind (`r = min(n, 20000)` distinct keys in a random order,
  `20000 / r` times over), each kind timed in batches of 100 inputs, with every input built
  before its batch's clock starts. Per input, in µs, the median and 95th percentile of the
  batches:
  - **view (unwritten)**: `seen k v` on a key never written: the view's value is taken;
  - **set**: `set k not` on an idle key: shows at once and sends a write;
  - **acked**: the write's 2xx: the key settles;
  - **lost**: another set, then its reply lost: the key is in doubt and sends a read;
  - **read back**: the read's answer, the write applied: the key settles;
  - **view (written, disagrees)**: `seen` on a written key with a value it doesn't show: a read
    to check it;
  - **check's read**: that read's answer, which the key takes.

  Every key ends settled (`allSettled`, checked). The outputs are kept, so nothing is optimised
  away.
- Keys are `Nat`, and then strings shaped like Sky's post URIs
  (`at://did:plc:…/app.bsky.feed.post/3l…`, 60 characters, compared from the front).

With `LEAN_ABORT_ON_NONLINEAR=1` no run aborts: the table is never copied while it is updated.

### Numbers

Apple M4 Max (Mac16,6), macOS 27.0.1, Lean 4.35.0, 2026-10-26, Cairn at `b576907` with this
bench (#256), release build (Lake's `-O3`), load average 3–4.5 from other agents' builds. Two
runs agreed within 10% at every size; this is the second. µs per input, p50 / p95.

`Nat` keys:

| Keys | Build (µs a key) | View, unwritten | Set | Acked | Lost | Read back | View, written | Check's read |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 | 0.16 | 0.097 / 0.100 | 0.135 / 0.137 | 0.112 / 0.115 | 0.135 / 0.137 | 0.114 / 0.116 | 0.127 / 0.130 | 0.102 / 0.104 |
| 1,000 | 0.15 | 0.132 / 0.144 | 0.175 / 0.186 | 0.148 / 0.160 | 0.175 / 0.187 | 0.150 / 0.158 | 0.165 / 0.173 | 0.138 / 0.141 |
| 10,000 | 0.16 | 0.205 / 0.211 | 0.245 / 0.261 | 0.213 / 0.222 | 0.238 / 0.247 | 0.220 / 0.225 | 0.235 / 0.245 | 0.203 / 0.207 |
| 100,000 | 0.18 | 0.366 / 0.494 | 0.374 / 0.389 | 0.335 / 0.350 | 0.373 / 0.393 | 0.345 / 0.360 | 0.362 / 0.373 | 0.322 / 0.333 |
| 1,000,000 | 0.23 | 0.967 / 1.215 | 0.959 / 1.091 | 1.005 / 1.120 | 0.999 / 1.091 | 1.008 / 1.118 | 0.987 / 1.080 | 0.999 / 1.104 |

Post URI keys:

| Keys | Build (µs a key) | View, unwritten | Set | Acked | Lost | Read back | View, written | Check's read |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 | 0.20 | 0.136 / 0.168 | 0.180 / 0.217 | 0.147 / 0.179 | 0.175 / 0.211 | 0.149 / 0.187 | 0.173 / 0.206 | 0.125 / 0.157 |
| 1,000 | 0.21 | 0.195 / 0.219 | 0.239 / 0.288 | 0.216 / 0.255 | 0.237 / 0.286 | 0.212 / 0.261 | 0.227 / 0.275 | 0.200 / 0.248 |
| 10,000 | 0.28 | 0.324 / 0.373 | 0.351 / 0.382 | 0.330 / 0.400 | 0.353 / 0.413 | 0.327 / 0.382 | 0.336 / 0.391 | 0.310 / 0.355 |
| 100,000 | 0.33 | 0.469 / 0.539 | 0.477 / 0.515 | 0.435 / 0.467 | 0.459 / 0.487 | 0.437 / 0.467 | 0.452 / 0.484 | 0.416 / 0.438 |
| 1,000,000 | 0.41 | 1.048 / 1.210 | 0.928 / 1.015 | 0.852 / 0.942 | 0.917 / 1.032 | 0.852 / 0.944 | 0.902 / 0.989 | 0.892 / 0.989 |

Building 1,000,000 keys took 231 ms (`Nat`) and 413 ms (post URIs).

Reading:

- **Every input is about a microsecond or less at 1,000,000 keys**, and a tenth to a quarter of
  one at the sizes an app holds (a feed of 1,000 posts has 1,000 to a few thousand keys per
  table). Against the 8 ms frame budget, a press costs the table under 0.01%.
- **Growth is about logarithmic up to 100,000** (the tree's depth: each tenfold adds 40–130 ns
  for `Nat` keys and 60–130 ns for URIs, which compare a 60-character string per level, more
  as the tree outgrows the faster caches). From 100,000
  to 1,000,000 it is 2.5×, more than one more level: the tree no longer fits in cache, and a
  random key misses on most levels. The keys here are random on purpose; a person presses posts
  near each other.
- **The kinds of input cost the same**: each is one lookup, one entry step and one insert
  (`Table.feed`). Those that send something (set, lost, a disagreeing view) cost 10–30 ns more,
  for the output.

## Press → frame: the fixture's Like

`cairn bench` on test/fixture (`Fixture --bench`, run by `make bench`), the "Likes" lines: the
app's real exports and the v1 codec with no threads, as the fixture's other input → frame lines
(bench/basics.md). Each sample is a press of post 1's Like (`^21#1`: pointer move, down, up)
encoded (Swift) → `cairn_app_step` (route, `update`, the table's `set`, the write's request,
view, layout with Core Text metrics, settle and the virtual list's record) → `cairn_app_frame`
(`Frame.ofLaid`, encode) → decode (Swift). The frame must carry exactly one write (`PUT`) and
show the post's new value (its AX node's `checked`), or the bench fails. Then, timed apart,
the write's `200` through its frame, so every press is on an idle post and sends a write. 50
samples after 10 warm-up. The window is the fixture's 480 × 600 at 2x with no items, so the
Like buttons are in it, and the fixture's virtual list of 10,000 rows below them.

### Numbers

Same machine, 2026-10-26, Cairn at `b576907` with this bench, release, `LEAN_ABORT_ON_NONLINEAR=1`,
load average 3–4 from other agents' builds. Four runs; the range of their p50s and p95s.

| Input → frame | p50 | p95 |
|---|---:|---:|
| Like press, with its write | 0.197–0.309 ms | 0.212–0.389 ms |
| The write's `200` | 0.108–0.169 ms | 0.117–0.214 ms |

The first run was the slowest of the four (0.309 / 0.389 and 0.169 / 0.214 ms); the other
three were within 5% of each other.

Reading:

- **A press shows in the next frame, 0.2 ms after it**: 2.5% of the 8 ms budget. The frame is
  the one the step produces; the press is in it (checked), with its write.
- Painting it adds the renderer's time for the fixture's ~120 draws, a fraction of bench/render.md's
  1,000 rects (0.02–0.03 ms CPU, 0.22 ms GPU at 2x).
- What this does not measure: the host's threads (bench/effects.md has the hop), the network
  (the fixture's server is in-process; press → confirmed against Sky's fake PDS is Sky's
  bench), and a feed of 1,000 posts, each with its own buttons (Sky's).
