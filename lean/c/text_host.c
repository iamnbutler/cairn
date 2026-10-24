// Glue between Lean's `@[extern]` text metrics (Cairn/Text/Host.lean) and the host's C ABI.
//
// The host (Swift, host/Sources/CairnRender/Metrics.swift) exports
//
//   int32_t cairn_text_metrics(uint32_t family, uint32_t size, uint32_t weight, uint8_t style,
//                              int32_t tracking, const uint8_t *utf8, size_t len, int32_t *out,
//                              size_t cap);
//
// `style` is bit 0 italic, bit 1 tabular digits, bits 2-3 the width (0 standard, 1 condensed,
// 2 expanded, 3 compressed); `tracking` is in hundredths of a point.
//
// which writes [ascent, descent, offset_0 .. offset_n] (n = Unicode scalars) and returns n + 3.
// This file wraps it in Lean's calling convention and returns the values as a little-endian
// ByteArray, which Lean decodes and normalises (so `TextMetrics.host` is `Valid` by proof,
// whatever bytes arrive).
//
// Executables that don't link the host (bench, audit, Lean tests) still link: the weak
// definition below stands in and reports "no host" (-1), and Lean falls back to the mono
// metrics. A strong definition from the Swift host replaces it at link time.
#include <lean/lean.h>
#include <stdint.h>
#include <string.h>

__attribute__((weak, noinline)) int32_t cairn_text_metrics(
    uint32_t family, uint32_t size, uint32_t weight, uint8_t style, int32_t tracking,
    const uint8_t *utf8, size_t len, int32_t *out, size_t cap) {
    (void)family; (void)size; (void)weight; (void)style; (void)tracking; (void)utf8; (void)len;
    (void)out; (void)cap;
    return -1;
}

// Returns n + 3 little-endian int32s, or an empty ByteArray if the host is absent or disagrees
// about the scalar count.
LEAN_EXPORT lean_obj_res cairn_lean_text_metrics(uint32_t family, uint32_t size, uint32_t weight,
                                                 uint8_t style, uint32_t tracking,
                                                 b_lean_obj_arg s) {
    size_t scalars = lean_string_len(s);
    size_t count = scalars + 3;
    lean_object *out = lean_alloc_sarray(1, count * 4, count * 4);
    int32_t *buf = (int32_t *)lean_sarray_cptr(out);  // Lean's allocator aligns to 8
    int32_t got = cairn_text_metrics(family, size, weight, style, (int32_t)tracking,
                                     (const uint8_t *)lean_string_cstr(s), lean_string_size(s) - 1,
                                     buf, count);
    if (got < 0 || (size_t)got != count) {
        lean_to_sarray(out)->m_size = 0;
        return out;
    }
    // Apple silicon and x86 are little-endian, which is the byte order Lean decodes.
    return out;
}

// 1 when a host implementation is linked, 0 when the weak stand-in is in use.
LEAN_EXPORT uint8_t cairn_lean_text_host_linked(lean_object *unit) {
    (void)unit;
    return cairn_text_metrics(0, 13, 400, 0, 0, (const uint8_t *)"", 0, NULL, 0) >= 0;
}
