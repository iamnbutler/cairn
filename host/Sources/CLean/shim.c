#include "cairn_lean.h"
#include <lean/lean.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Declared by the runtime but not in lean.h.
extern void lean_initialize_thread(void);
extern void lean_finalize_thread(void);
extern lean_object *initialize_cairn_Examples(uint8_t builtin);

void cairn_lean_init(void) {
    lean_initialize_runtime_module();
    lean_object *res = initialize_cairn_Examples(1);
    if (!lean_io_result_is_ok(res)) {
        lean_io_result_show_error(res);
        abort();
    }
    lean_dec_ref(res);
    lean_io_mark_end_initialization();
}

void cairn_lean_thread_begin(void) { lean_initialize_thread(); }
void cairn_lean_thread_end(void) { lean_finalize_thread(); }
void cairn_lean_inc(lean_object *o) { lean_inc(o); }
void cairn_lean_dec(lean_object *o) { lean_dec(o); }

lean_object *cairn_bytes_new(const uint8_t *data, size_t size) {
    lean_object *b = lean_alloc_sarray(1, size, size);
    if (size) memcpy(lean_sarray_cptr(b), data, size);
    return b;
}
const uint8_t *cairn_bytes_data(lean_object *b) { return lean_sarray_cptr(b); }
size_t cairn_bytes_size(lean_object *b) { return lean_sarray_size(b); }
