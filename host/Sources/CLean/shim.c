#include "cairn_lean.h"
#include <lean/lean.h>
#include <stdlib.h>
#include <string.h>

// Declared by the runtime but not in lean.h.
extern void lean_initialize_thread(void);
extern void lean_finalize_thread(void);
extern void lean_initialize_runtime_module(void);

#define L(o) ((lean_object *)(o))
#define C(o) ((cairn_obj *)(o))

void cairn_lean_init(const cairn_module_init *inits, size_t count, uint8_t exit_on_panic) {
    lean_initialize_runtime_module();
    lean_set_exit_on_panic(exit_on_panic != 0);
    for (size_t i = 0; i < count; i++) {
        lean_object *res = L(inits[i](1));
        if (!lean_io_result_is_ok(res)) {
            lean_io_result_show_error(res);
            abort();
        }
        lean_dec_ref(res);
    }
    lean_io_mark_end_initialization();
}

void cairn_lean_thread_begin(void) { lean_initialize_thread(); }
void cairn_lean_thread_end(void) { lean_finalize_thread(); }
void cairn_lean_inc(cairn_obj *o) { lean_inc(L(o)); }
void cairn_lean_dec(cairn_obj *o) { lean_dec(L(o)); }

cairn_obj *cairn_bytes_new(const uint8_t *data, size_t size) {
    lean_object *b = lean_alloc_sarray(1, size, size);
    if (size) memcpy(lean_sarray_cptr(b), data, size);
    return C(b);
}
const uint8_t *cairn_bytes_data(cairn_obj *b) { return lean_sarray_cptr(L(b)); }
size_t cairn_bytes_size(cairn_obj *b) { return lean_sarray_size(L(b)); }
