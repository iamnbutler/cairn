// The C boundary between the Swift host and the Lean library.
// Lean's own header is vendored into ../vendor by `make lean` (not committed).
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

// Module initializers of the Lake libraries linked into libcairn_lean.a.
// `Cairn` must be initialized before Lean measures text (`TextMetrics.host`, docs/render.md).
cairn_obj *initialize_cairn_Cairn(uint8_t builtin);
cairn_obj *initialize_cairn_Examples(uint8_t builtin);

// Exported from Examples/Counter.lean (frame v0, docs/spike-boundary.md). Every argument is
// owned (consumed). The v1 app ABI is `<app>_init(w, h, scalePercent)`, `<app>_step(state,
// events)`, `<app>_frame(state)`; see docs/host.md.
cairn_obj *cairn_counter_new(uint32_t w, uint32_t h);
cairn_obj *cairn_counter_step(cairn_obj *state, cairn_obj *events);
cairn_obj *cairn_counter_frame(cairn_obj *state);
uint32_t cairn_counter_count(cairn_obj *state);
cairn_obj *cairn_bench_frame(uint32_t n);
