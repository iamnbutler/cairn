module

public import Cairn.Claims.Move
public import Cairn.Claims.Machine

/-! The runtime half of the claim language: moves, dispatch, machines, flows, invariants,
assumptions and places, with their theorems. Pure; no `Lean` import, so it links into the host.
Apps import `Cairn.Claims`, which brings this in together with the commands. -/

@[expose] public section

