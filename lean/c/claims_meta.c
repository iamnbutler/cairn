// Stand-ins for the initializers of `Cairn.Claims.Elab` (the claim commands), for binaries that
// do not link the Lean compiler (the Swift host).
//
// Apps are `module`s that `meta import Cairn.Claims.Elab`: the commands run at compile time, and
// nothing they generate needs them at run time. The module system keeps them out of an app's
// `runtime_initialize_*` chain, which is what the host calls, so the host never runs this. But
// each app module's object file also contains its full `initialize_*` and its
// `meta_initialize_*`, which do call the commands' initializers, and the linker resolves every symbol in an object it links, used or not.
// These weak definitions satisfy those references without pulling in `Lean` (~100 MB). If anything
// does call it, it fails loudly instead of initializing half a module.
//
// Executables that link the real module (`lake exe ledger`, `claims`, `bench`) get its strong
// definitions; the linker prefers them to these weak ones.
#include <lean/lean.h>

static lean_object *compile_time_only(void) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(
        "Cairn.Claims.Elab (the claim commands) is compile-time only; call the app's "
        "runtime_initialize_* instead of initialize_*")));
}

__attribute__((weak)) lean_object *initialize_cairn_Cairn_Claims_Elab(uint8_t builtin) {
    (void)builtin;
    return compile_time_only();
}

__attribute__((weak)) lean_object *runtime_initialize_cairn_Cairn_Claims_Elab(uint8_t builtin) {
    (void)builtin;
    return compile_time_only();
}
