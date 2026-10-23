// Lean's side of the trusted-base fuzzer (lean/Cairn/Fuzz/Trusted/Export.lean), linked from
// build/lib/libcairn_trusted_fuzz.a by cairn-fuzz-trusted only. Every Lean argument is owned.
#pragma once
#include "cairn_lean.h"

cairn_obj *initialize_cairn_Cairn_Fuzz_Trusted_Export(uint8_t builtin);

// A random, valid, encoded frame for a seed.
cairn_obj *cairn_tf_gen_frame(uint64_t seed);
// Lean's proved decoders on any bytes: "R", or "A=" / "A~" followed by the canonical dump.
cairn_obj *cairn_tf_decode_frame(cairn_obj *bytes);
cairn_obj *cairn_tf_decode_events(cairn_obj *bytes);

// A one-field app on the real runtime, with the cairn_app_* ABI under other names.
cairn_obj *cairn_tf_field_init(uint32_t w, uint32_t h, uint32_t scale_percent);
cairn_obj *cairn_tf_field_step(cairn_obj *state, cairn_obj *events);
cairn_obj *cairn_tf_field_frame(cairn_obj *state);

// `TextMetrics.host` as layout sees it (Cairn/Text/Host.lean, in libcairn_lean.a):
// int32s [linked, ascent, descent, offset_0, ..., offset_n] for UTF-8 `s`.
cairn_obj *cairn_tf_host_metrics(uint32_t family, uint32_t size, uint32_t weight, uint8_t italic,
                                 const uint8_t *utf8, size_t len);
