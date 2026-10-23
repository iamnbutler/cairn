---
title: "FFI and embedding Lean 4.35 in a Swift host"
urls:
  - https://lean-lang.org/doc/reference/latest/Run-Time-Code/Foreign-Function-Interface/
  - https://github.com/paulcadman/lean-ios
  - https://github.com/paulcadman/lean4/tree/ios
  - https://github.com/leanprover/lean4/pull/13017
  - https://github.com/leanprover/lean4/pull/14505
date: 2026-10-23
relevance: 5
---

# FFI and embedding Lean 4.35 in a Swift host

The spike (`docs/spike-boundary.md`) already embeds Lean; this note confirms its findings against
the toolchain and adds what will matter as the boundary grows. "Observed" means run against
4.35.0: `/tmp/cl/Ffi.lean` compiled with `lean -c`, and the C host in
[raw/runtime-experiments/host.c](raw/runtime-experiments/host.c).

## Ownership and borrowing at the boundary

- **`@&` on an `@[export]` parameter is an error in 4.35 (confirmed).** Observed:
  `Declaration fBorrow is marked as `export` but some of its parameters have borrow annotations.
  Consider using `set_option compiler.ignoreBorrowAnnotation true in` to suppress the borrow
  annotations in its type.` Source: `Lean/Compiler/LCNF/ToDecl.lean:93`. Release notes: 4.30
  #13017 (and lean-ios's base history shows the earlier steps, #12930 "ignore borrow annotations
  at export/extern tricks" and #12952 "actively ignore borrow annotations for export functions").
  The manual: "Return values and `@[export]` parameters are always owned at the moment."
- **Owned means the callee consumes it.** Observed generated C for `@[export f_s] def fS (s : S)
  : UInt32 := s.a`: `v_a_16_ = lean_ctor_get_uint32(v_s_15_, 8); lean_dec_ref(v_s_15_);`. Swift
  must `lean_inc` anything it still needs before every call (the spike's `cairn_lean_inc`).
- **`@[extern]` may borrow:** `@[extern "my_c_fn"] opaque myC (a : @& ByteArray) : UInt32`
  compiled to `uint32_t my_c_fn(lean_object*);` with no `dec` by the caller's contract; the
  manual: "By default, all `lean_object *` parameters of an `extern` function are considered
  _owned_. Parameters may be marked as borrowed by prefixing their types with `@&`." This is the
  right shape for `cairn_text_offsets` (workstream F): borrow the string, return a new array.

## Representation

- Manual: fixed-width integers are `uint8_t … uint64_t`, `size_t`; "If their run-time
  representation requires boxing, then they are unboxed at the FFI boundary"; `Char` is
  `uint32_t`; `Float` is `double`; `Nat`/`Int` are `lean_object *`; "it is not yet possible to
  pass or return compound data structures such as C `struct`s by value".
  Observed: `@[export f_u32] def fU32 (x : UInt32) (b : ByteArray) : UInt32` →
  `LEAN_EXPORT uint32_t f_u32(uint32_t, lean_object*);`.
- **Structure field order is not declaration order.** For `structure S where (a : UInt32)
  (b : Float)`, the generated accessor reads `a` at scalar offset **8**
  (`lean_ctor_get_uint32(v_s_15_, 8)`): the compiler sorts scalar fields by size (the `Float`
  comes first). Swift must never compute Lean object layouts by hand; read them through exported
  Lean accessors, or (our design) only exchange `ByteArray` frames, whose format we specify.

## Initialization

- Observed generated initializer (`lean -c`):

  ```c
  LEAN_EXPORT lean_object* initialize_Ffi(uint8_t builtin) {
  if (_G_initialized) return lean_io_result_mk_ok(lean_box(0));
  _G_initialized = true;
  lean_initialize_runtime_module();
  res = initialize_Init(builtin); ...
  ```

  So: one `builtin` argument, no world argument (4.26 #10625), and it calls
  `lean_initialize_runtime_module` itself (4.34 #14505). The manual: initializers "are also
  idempotent (when run with the same `builtin` flag), but not thread-safe" — call once, from one
  thread, before anything else. Then `lean_io_mark_end_initialization()` (declared,
  `lean.h:3189`); the manual's sample and Lake's generated `main` both do this.
- **Undeclared runtime entry points.** `lean_initialize_runtime_module`,
  `lean_initialize_thread` and `lean_finalize_thread` are exported from `libleanrt.a` (`nm`:
  `T _lean_initialize_thread`, `T _lean_finalize_thread`, `T _lean_initialize_runtime_module`)
  but not declared in `lean.h` (grep finds none). A shim must declare them (our spike and
  lean-ios both do: `extern void lean_initialize_thread(void);`).
- **Threads.** Manual: "any other thread not spawned by the Lean runtime itself must be
  initialized for Lean use by calling `void lean_initialize_thread();`" and finalized with
  `lean_finalize_thread()`. The task manager is only needed "for code that (indirectly) uses
  `Task`" (`lean_init_task_manager`, `lean.h:1547`). Our pure core doesn't, and shouldn't
  (note 03: sharing state with a task marks it multi-threaded and defeats in-place updates).
- **Stack size.** The host-created Lean thread needs a large stack. Observed: structural
  recursion over a box with 30,000 children crashes (SIGILL) on a 512 KB pthread stack, 300,000
  on 8 MB; 64 MB handled 1,000,000 (details in note 03).
- **Panics.** By default a `panic!` prints and returns `default`, so the app keeps running with a
  wrong value. `lean_set_exit_on_panic(bool)` and `lean_set_panic_messages(bool)` are declared
  (`lean.h:418-420`). Cedar's host sets exit-on-panic (note 04); we should in debug and test builds.

## Linking

- Plain Lean code needs `libInit`, `libleanrt`, `libuv`, `libgmp` and `-lc++`; observed: a C host
  linked with exactly those (`xcrun clang … libInit.a libleanrt.a libuv.a libgmp.a -lc++`), matching
  the spike's `Makefile`. Add `libStd.a` once anything imports `Std`.
- `leanc` (the bundled clang) can't compile host C that includes system headers on macOS without
  extra flags (`'pthread.h' file not found` even with `-isysroot`); compile host code with Xcode's
  clang and `-I$(lean --print-prefix)/include`.
- Any transitive `import Lean` pulls in `libLean` (101 MB binary in the note-05 experiment). Keep
  `import Lean` out of anything the host links.

## Precedent: lean-ios (paulcadman/lean-ios)

Summarised from the sub-agent's review of the repo (last push 2026-04-22, 7 stars):

- Pins `leanprover/lean4:v4.29.0` plus a fork (`paulcadman/lean4`, branch `ios`) with two commits:
  "Add USE_LIBUV flag to avoid compiling code depending on libuv" and "Fix no-libuv Lean runtime
  builds for iOS embedding" (stubs returning `lean_mk_io_error_unsupported_operation` for
  `lean_uv_tcp_*`/`udp_*`).
- Builds the runtime with CMake for iOS (`-DCMAKE_SYSTEM_NAME=iOS -DUSE_MIMALLOC=OFF
  -DUSE_LIBUV=OFF -DUSE_GMP=OFF`) and recompiles `Init`/`Std`/`Lean` from the fork's
  `stage0/stdlib` C with an `xcrun --sdk … clang` wrapper. The macOS toolchain's `.a` files
  can't be reused for iOS.
- Initialization in `app-common/native/LeanRuntimeBridge.c`:
  `lean_initialize_runtime_module(); lean_initialize_thread(); … LEAN_APP_ROOT_MODULE(1)` with
  hand-declared externs, the same as our spike. The minimal example instead calls C++ internals
  (`lean::initialize_alloc()`), which is fragile.
- Lean owns the loop there (SDL callbacks, state in `IO.Ref`), all on one thread. Precedent for
  build and init only; not for our three-thread, pure-core architecture.
- No other Lean-in-Swift projects were found.

Cedar's Rust FFI still passes a world argument to module initializers (older Lean) and notes it
"can only have one Lean thread" (note 04). That matches our design: one Lean thread owns the state.

## Counter-evidence

- The manual's FFI page doesn't mention `lean_initialize_runtime_module` or the undeclared thread
  functions' missing prototypes, and older examples online (Cedar's Rust, pre-4.26 posts) pass a
  world argument. Trust the generated C for the pinned version, and re-check it on every bump.
- `compiler.ignoreBorrowAnnotation` exists to share a type between an `extern` and `export` pair;
  using it hides ownership from readers. Prefer separate signatures.

## For Cairn

- **G (host):** call `initialize_<Root>(1)` once on the Lean thread, then
  `lean_io_mark_end_initialization()`; `lean_initialize_thread()` on that thread first if it isn't
  the one that ran the initializer; create it with ≥ 64 MB stack; `lean_set_exit_on_panic(true)`
  in debug/test. Every argument to an export is owned: `lean_inc` before passing anything Swift
  keeps. Record all of this in `docs/trusted.md`.
- **E (encoding):** the frame `ByteArray` is the only structured data crossing the boundary; don't
  export functions taking or returning Lean structures to Swift.
- **F (renderer/text):** `cairn_text_offsets` as `@[extern]` with `@&` on the string is allowed
  and avoids a refcount round trip; it returns an owned array.
- **A (claims):** no `import Lean` in anything linked into the host (note 05).
