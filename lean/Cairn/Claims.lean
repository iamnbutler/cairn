import Cairn.Claims.Core
import Cairn.Claims.Elab

/-! Claims as a language feature. Import this to declare claims with `move`, `flow`,
`invariant`, `assume`, `place` and `retire`, and to collect them with `moves%` and `claims%`.
See `docs/claims.md`.

**Linking.** This module imports `Lean` for the commands, but nothing it adds is needed at run
time except `Cairn.Claims.Core`. The host does not link the Lean compiler, so the Makefile
links `Cairn/Claims/host_init.c` in place of this module's compiled initializer: it initializes
`Cairn.Claims.Core` and nothing else. For that to stay true, keep every runtime definition in
`Core` (or modules it imports), and never import this module from `Cairn.lean`. -/
