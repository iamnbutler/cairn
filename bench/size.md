# Binary size

Release, stripped size of each app executable, and where the bytes come from. Apple M4 Max,
macOS 27, Swift 6 (Xcode), Lean 4.35.0, 2026-10-23, Counter and Basics on the v1 ABI.

| App | Stripped | Before strip |
|---|---:|---:|
| CairnCounter | 2,439,264 B (2.44 MB) | 3,822,288 B |
| CairnBasics | 2,490,072 B (2.49 MB) | 3,885,464 B |
| CairnTodo | not yet (add it to `SIZE_APPS` when it lands) | |

MB here is 10⁶ bytes. Before the move to v1, the v0 Counter measured the same way on
`324ef0a` was 2,405,280 B: the v1 runtime, layout and frame codec cost Counter about 34 KB. (The
earlier figure, 2.25 MB, was taken on an older tree; 2,405,280 B is 2.29 MiB.)

## Breakdown

Bytes the linker kept, attributed from the link map (`-Xlinker -map`), by where each live
symbol came from. Release links dead-strip, so only what is reachable counts.

| | CairnCounter | | CairnBasics | |
|---|---:|---:|---:|---:|
| Lean runtime: Init and Std (compiled Lean) | 1,153,665 | 47.3% | 1,153,853 | 46.3% |
| Lean runtime: leanrt, libuv, libgmp (C/C++) | 432,811 | 17.7% | 433,939 | 17.4% |
| Cairn framework (Lean: runtime, layout, frame, text) | 223,205 | 9.2% | 246,437 | 9.9% |
| The app's library (`libcairn_app_<app>.a`) | 9,100 | 0.4% | 21,632 | 0.9% |
| Swift host | 450,111 | 18.5% | 463,807 | 18.6% |
| Metal shader source | 3,753 | 0.2% | 3,753 | 0.2% |
| Linker, other | 166,619 | 6.8% | 166,651 | 6.7% |

Swift host by target (CairnCounter): CairnHost 230,466; CairnRender 77,877 (without the shader
string); CairnCapture 71,081; CairnFrame 46,262; the app's `main.swift` 23,841; CLean 584.

- **Lean runtime** is about two thirds of every app and the same in each: `Init`/`Std` code the
  framework reaches, plus the C++ runtime, libuv and GMP. It doesn't grow with the app.
- **Cairn** is the framework's compiled Lean; Basics reaches more of it (text fields).
- **The app** itself is small: Counter's model, view and exports are 9 KB.
- **Metal shaders** ship as source and are compiled at launch (`device.makeLibrary(source:)`), so
  they are one string in CairnRender, 3.7 KB. There is no `.metallib` and no resource bundle; the
  executable is the whole app.
- **Linker, other** is the stripped size minus everything attributed: stubs, unwind tables,
  Objective-C and Swift metadata the linker synthesizes, the dynamic-symbol and fixup tables left
  after `strip`, and page padding.
- System frameworks and the Swift runtime are dynamic libraries in the OS, not in the binary.
- Linking `Lean` (the compiler) instead adds about 100 MB (research/lean/05); that is what the
  guard below is for.

## How it is measured

`make size` (part of `make check`) runs, for each app in `SIZE_APPS`:

```sh
cd host
swift build -c release --product CairnCounter -Xlinker -map -Xlinker $PWD/../build/size/CairnCounter.map
cd ..
bun tools/size/size.ts --bin $(cd host && swift build -c release --show-bin-path) \
    --maps build/size --out build/size --limit 5000000 CairnCounter CairnBasics
```

`tools/size/size.ts` strips a copy of each binary (`strip -o build/size/<App> <bin>/<App>`,
which removes every local and debug symbol, as for a shipped binary), prints the size and the
breakdown, writes `build/size/size.json`, and attributes bytes from the map's live symbols:

- an object from `build/lib/libcairn_app_<app>.a` is the app;
- an object from `build/lib/libcairn_lean.a` is Cairn if any of its symbols names `Cairn`,
  otherwise compiled Lean (`*.c.o`) is Init/Std and anything else is leanrt, libuv or libgmp;
- an object under `host/.build/` is the Swift host, by target;
- the string literal starting `#include <metal_stdlib>` is the shader source.

The stripped binaries still run: `build/size/CairnCounter --selftest` and
`build/size/CairnBasics --selftest` pass.

## The guard

`make size` fails if any app's stripped binary is over `SIZE_LIMIT` (5,000,000 bytes). No host
app may `import Lean` (AGENTS.md), so each is a couple of MB and has about 2.5 MB of headroom;
an app that links the compiler is about 100 MB and fails at once. Raise the limit only with a
measurement here that says why.
