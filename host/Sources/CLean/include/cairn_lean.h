// The C boundary between the Swift host and the Lean library.
// Lean's own header is vendored into ../vendor by `make lean` (not committed).
#pragma once
#include <stdint.h>
#include <stddef.h>

// Opaque to Swift (an OpaquePointer). lean.h defines the real lean_object, so the header
// uses its own name and the shim casts.
typedef struct cairn_obj cairn_obj;

// Runtime
void cairn_lean_init(void);          // once, on the main thread, before anything else
void cairn_lean_thread_begin(void);  // on every thread Lean did not create, before calling in
void cairn_lean_thread_end(void);
void cairn_lean_inc(cairn_obj *o);
void cairn_lean_dec(cairn_obj *o);

// Byte arrays
cairn_obj *cairn_bytes_new(const uint8_t *data, size_t size);
const uint8_t *cairn_bytes_data(cairn_obj *b);
size_t cairn_bytes_size(cairn_obj *b);

// Exported from Examples/Counter.lean. Every argument is owned (consumed).
cairn_obj *cairn_counter_new(uint32_t w, uint32_t h);
cairn_obj *cairn_counter_step(cairn_obj *state, cairn_obj *events);
cairn_obj *cairn_counter_frame(cairn_obj *state);
uint32_t cairn_counter_count(cairn_obj *state);
cairn_obj *cairn_bench_frame(uint32_t n);
