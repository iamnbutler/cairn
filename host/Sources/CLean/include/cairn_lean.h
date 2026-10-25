// The C boundary between the Swift host and the Lean library.
// Lean's own header is committed in ../vendor (copied by `make lean` from the pinned toolchain).
#pragma once
#include <stdint.h>
#include <stddef.h>

// Opaque to Swift (an OpaquePointer). lean.h defines the real lean_object, so the header
// uses its own name and the shim casts.
typedef struct cairn_obj cairn_obj;

// A Lean module initializer, `initialize_<package>_<Module>(builtin)`. It returns an IO result.
typedef cairn_obj *(*cairn_module_init)(uint8_t builtin);

// Runtime. The host calls these from the Lean thread only (docs/host.md).
// `cairn_lean_init` initializes the runtime on the calling thread, then runs each module
// initializer in order (each is idempotent); it aborts with Lean's error if one fails. Call it
// once per process. `exit_on_panic`: a Lean `panic!` aborts instead of returning a default value
// (the host sets it in debug builds).
void cairn_lean_init(const cairn_module_init *inits, size_t count, uint8_t exit_on_panic);
void cairn_lean_thread_begin(void);  // on every other thread Lean did not create, before calling in
void cairn_lean_thread_end(void);
void cairn_lean_inc(cairn_obj *o);
void cairn_lean_dec(cairn_obj *o);

// Byte arrays
cairn_obj *cairn_bytes_new(const uint8_t *data, size_t size);
const uint8_t *cairn_bytes_data(cairn_obj *b);
size_t cairn_bytes_size(cairn_obj *b);

// The framework's initializer, in libcairn_lean.a: `Cairn.Abi`, the top of what apps link (the
// `Cairn` umbrella also imports the proofs, which aren't linked). It must run before Lean
// measures text (`TextMetrics.host`, docs/render.md).
cairn_obj *initialize_cairn_Cairn_Abi(uint8_t builtin);

// Everything below is defined by the app's own library, which the app's executable links next to
// this one (bin/cairn-link, docs/package.md).

// The v1 app ABI (docs/runtime.md), exported by every v1 app. Every argument is owned
// (consumed): `step` consumes the state and the event bytes and returns the new state; `frame`
// consumes the state (lean_inc it first to keep it) and returns the frame bytes (docs/frame.md).
cairn_obj *cairn_app_init(uint32_t w, uint32_t h, uint32_t scale_percent);
cairn_obj *cairn_app_step(cairn_obj *state, cairn_obj *events);
cairn_obj *cairn_app_frame(cairn_obj *state);

// App libraries are Lean `module`s whose apps may `meta import` the claim commands (which use the
// Lean compiler). Their `runtime_` initializers run only what the app needs at run time; the full
// `initialize_*` would also initialize the commands, and so all of `Lean`, which the host does
// not link (docs/claims.md, "Linking"). An app declares its own (`cairn new` writes the
// declaration into Sources/C<App>/include).
