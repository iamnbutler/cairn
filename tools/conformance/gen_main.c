// The conformance generator's entry point (docs/conformance.md).
//
// Lean emits a `main` only for a module's own `def main`, and that main runs the module's full
// initializer, which for an app module reaches the claim commands (compile time only; see
// lean/c/claims_meta.c). So the generator starts like the host does: the runtime, then `Cairn`
// (TextMetrics.host reads its state), then the app's generator module through its
// `runtime_initialize_*`, which the module system keeps clear of the commands. `make
// conformance` compiles this file with -DCAIRN_APP_INIT=runtime_initialize_cairn_Conformance_Apps_<App>.
#include <lean/lean.h>
#include <stdio.h>
#include <stdlib.h>

extern void lean_initialize_runtime_module(void);
extern lean_object *initialize_cairn_Cairn(uint8_t builtin);
extern lean_object *CAIRN_APP_INIT(uint8_t builtin);
extern lean_object *cairn_conformance_run(lean_object *args, lean_object *world);

static void check(lean_object *res) {
    if (!lean_io_result_is_ok(res)) {
        lean_io_result_show_error(res);
        exit(1);
    }
    lean_dec_ref(res);
}

int main(int argc, char **argv) {
    lean_initialize_runtime_module();
    lean_set_panic_messages(true);
    check(initialize_cairn_Cairn(1));
    check(CAIRN_APP_INIT(1));
    lean_io_mark_end_initialization();

    lean_object *args = lean_box(0);  // List.nil
    for (int i = argc - 1; i >= 1; i--) {
        lean_object *cell = lean_alloc_ctor(1, 2, 0);
        lean_ctor_set(cell, 0, lean_mk_string(argv[i]));
        lean_ctor_set(cell, 1, args);
        args = cell;
    }
    lean_object *res = cairn_conformance_run(args, lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
        lean_io_result_show_error(res);
        return 1;
    }
    uint32_t code = lean_unbox_uint32(lean_io_result_get_value(res));
    lean_dec_ref(res);
    return (int)code;
}
