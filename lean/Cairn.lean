module

public import Cairn.Geometry
public import Cairn.Claim
public import Cairn.Effects
public import Cairn.Font
public import Cairn.Input
public import Cairn.UI.Node
public import Cairn.UI.Images
public import Cairn.UI.Grid
public import Cairn.UI.Hit
public import Cairn.Surface
public import Cairn.App
public import Cairn.Claims.Move
public import Cairn.Claims.Machine
public import Cairn.Claims.Core
public meta import Cairn.Claims.Elab
public import Cairn.Text.Wrap
public import Cairn.Text.Field
public import Cairn.Text.Host
public import Cairn.Layout.Core
public import Cairn.Layout.Facts
public import Cairn.Runtime.World
public import Cairn.Runtime.Step
public import Cairn.Runtime.Abi
public import Cairn.Frame
public import Cairn.Frame.Bytes
public import Cairn.Frame.Encode
public import Cairn.Frame.Events
public import Cairn.Frame.Menu
public import Cairn.Frame.Build
public import Cairn.Abi
public import Cairn.Fuzz.Rng

/-! # Cairn

What an app imports: `import Cairn` (in a `module`, `public import Cairn`). It brings in every
module of the `Cairn` library, the code `bin/cairn-link` links into an app (lakefile.lean): the
app model, layout, text, the runtime and its ABI (`Cairn.Abi`, `Cairn.Runtime.Abi`,
`Cairn.Text.Host`), effects, and the claim language, whose commands it `meta`-imports so they
run at compile time only (docs/claims.md, "Linking"). No proofs, no `import Lean` at run time.

The proofs, tests and tools are in other libraries, and `CairnAll` imports them all for the
ledger, the axiom audit and the docs. Keep this list to the `Cairn` library's roots: a module
outside it would make every app's link fail (`bin/cairn-link` warns). -/
