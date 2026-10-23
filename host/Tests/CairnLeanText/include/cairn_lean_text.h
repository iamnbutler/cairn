// Test support: call Lean's `TextMetrics.host` from Swift, to check end to end that the numbers
// Lean lays out with are the numbers the renderer draws with (host/Tests/CairnRenderLeanTests).
#pragma once
#include <stdint.h>
#include <stddef.h>

// Initialises the Lean runtime and the Cairn library, once, on the calling thread.
void cairn_text_test_init(void);

// Fills `out` with [linked, ascent, descent, offset_0, …] as Lean computes them through
// `TextMetrics.host`; returns how many int32s the full result has.
size_t cairn_text_test_lean_metrics(uint32_t family, uint32_t size, uint32_t weight, uint8_t italic,
                                    const uint8_t *utf8, size_t len, int32_t *out, size_t cap);
