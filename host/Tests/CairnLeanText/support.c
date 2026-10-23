#include "cairn_lean_text.h"
#include "cairn_lean.h"
#include <stdlib.h>
#include <string.h>

// Real (non-inline) functions of the Lean runtime, so this file needs no lean.h.
extern void lean_initialize_runtime_module(void);
extern void lean_io_mark_end_initialization(void);
extern cairn_obj *lean_mk_string_from_bytes(const char *s, size_t sz);
extern cairn_obj *initialize_cairn_Cairn(uint8_t builtin);
// Exported from Cairn/Text/Host.lean. Arguments are owned.
extern cairn_obj *cairn_text_host_check(uint32_t family, uint32_t size, uint32_t weight,
                                        uint8_t italic, cairn_obj *s);

void cairn_text_test_init(void) {
    static int done = 0;
    if (done) return;
    done = 1;
    lean_initialize_runtime_module();
    cairn_obj *res = initialize_cairn_Cairn(1);
    cairn_lean_dec(res);
    lean_io_mark_end_initialization();
}

size_t cairn_text_test_lean_metrics(uint32_t family, uint32_t size, uint32_t weight, uint8_t italic,
                                    const uint8_t *utf8, size_t len, int32_t *out, size_t cap) {
    cairn_obj *s = lean_mk_string_from_bytes((const char *)utf8, len);
    cairn_obj *b = cairn_text_host_check(family, size, weight, italic, s);
    size_t n = cairn_bytes_size(b) / 4;
    memcpy(out, cairn_bytes_data(b), (n < cap ? n : cap) * 4);
    cairn_lean_dec(b);
    return n;
}
