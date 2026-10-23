module

public import Cairn.Claims.Core
public meta import Cairn.Claims.Elab

/-! Claims as a language feature: the runtime vocabulary (`Cairn.Claims.Core`) and the claim
commands (`move`, `flow`, `invariant`, `assume`, `place`, `retire`, `moves%`, `claims%`).
See `docs/claims.md`.

This umbrella is for non-module files (tests, tools). An app that the host links is a `module`
that writes `public import Cairn.Claims.Core` and `meta import Cairn.Claims.Elab` itself, so the
commands (which import `Lean`) stay out of its compiled code; see "Linking" in docs/claims.md. -/
