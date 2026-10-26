# Benchmarks

Numbers behind performance claims (AGENTS.md, "Measure, don't guess"). Each file says how to run
it (a `make` target or command), what it measures and how, and then its numbers with the machine,
the date, the commit or release measured and the load the machine was under.

| File | What |
|---|---|
| [basics.md](basics.md) | Basics: input → frame at 10 and 1,000 items (a record; the app is in cairn_examples) |
| [effects.md](effects.md) | effects: latency through the host, and timers |
| [frame.md](frame.md) | frame encoding (Lean) and decoding (Swift) at 1,000 and 10,000 nodes |
| [fuzz.md](fuzz.md) | the fuzzer's throughput |
| [layout.md](layout.md) | layout of 100 to 10,000 nodes, and wrapped paragraphs |
| [optimistic.md](optimistic.md) | `Cairn.Optimistic` at 100 to 1,000,000 keys (set, replies, read-back, views), and press → frame on the fixture's Like |
| [render.md](render.md) | the Metal renderer |
| [size.md](size.md) | release binary size, attributed |
| [surfaces.md](surfaces.md) | the overlay panel at 50 Hz, and the menu |
| [todo.md](todo.md) | TodoMVC: input → frame at 100 to 10,000 nodes (a record) |
| [vlist.md](vlist.md) | virtual lists of 100 to 100,000 rows: steps, and whole frames by phase (update, view, layout, settle, encode) during flings |

Apps' own benchmarks live in their repositories:

- **Sky** (M4, cairn#212): sign-in → first page and refresh → new posts against the fake PDS
  with 0 and 100 ms added, flings through 1,000 posts with images (the Lean step by phase, encode,
  decode and Metal render), memory after 1,000 posts and the image cache's budget, and Sky.app's
  size: [iamnbutler/sky bench/README.md](https://github.com/iamnbutler/sky/blob/main/bench/README.md).
