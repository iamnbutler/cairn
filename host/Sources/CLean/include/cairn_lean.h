// The C boundary between the Swift host and the Lean library.
// Lean's own header is vendored into ../vendor by `make lean` (not committed).
#pragma once
#include <stdint.h>
#include <stddef.h>

typedef struct lean_object lean_object;

// Runtime
void cairn_lean_init(void);          // once, on the main thread, before anything else
void cairn_lean_thread_begin(void);  // on every thread Lean did not create, before calling in
void cairn_lean_thread_end(void);
void cairn_lean_inc(lean_object *o);
void cairn_lean_dec(lean_object *o);

// Byte arrays
lean_object *cairn_bytes_new(const uint8_t *data, size_t size);
const uint8_t *cairn_bytes_data(lean_object *b);
size_t cairn_bytes_size(lean_object *b);

// Exported from Examples/Counter.lean. Every argument is owned (consumed).
lean_object *cairn_counter_new(uint32_t w, uint32_t h);
lean_object *cairn_counter_step(lean_object *state, lean_object *events);
lean_object *cairn_counter_frame(lean_object *state);
uint32_t cairn_counter_count(lean_object *state);
lean_object *cairn_bench_frame(uint32_t n);
