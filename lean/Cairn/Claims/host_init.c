// Stand-in initializer for the `Cairn.Claims` module in binaries that don't link the Lean
// compiler (the Swift host).
//
// Apps `import Cairn.Claims` to use the claim commands. That module imports `Lean`, so its real
// initializer (`initialize_cairn_Cairn_Claims`, compiled from Cairn/Claims.lean) initializes the
// whole of `Lean`, and linking it would pull libLean (~100 MB) into the host. Nothing the module
// adds is needed at run time except `Cairn.Claims.Core`: the commands run only at compile time,
// and everything they generate refers to `Core` and the app's own module. So this weak
// definition initializes `Core` and nothing else.
//
// Binaries that do link the real module (lake executables such as `ledger`, `claims` and
// `bench`) get its strong definition instead; the linker prefers it over this weak one.
//
// This holds only while `Cairn.Claims` adds no run-time code of its own beyond `Core`: keep every
// runtime definition in `Cairn.Claims.Core` or a module it imports, and never import
// `Cairn.Claims` from `Cairn.lean`.
#include <lean/lean.h>

lean_object *initialize_cairn_Cairn_Claims_Core(uint8_t builtin);

__attribute__((weak)) lean_object *initialize_cairn_Cairn_Claims(uint8_t builtin) {
    return initialize_cairn_Cairn_Claims_Core(builtin);
}
