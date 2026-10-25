import Lake
open Lake DSL

package cairn where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

/-- C glue for `Cairn.Text.Host`'s `@[extern]` metrics (see lean/c/text_host.c). It defines the
host's `cairn_text_metrics` weakly, so executables link without the Swift host. -/
target text_host.o pkg : System.FilePath := do
  let src ← inputTextFile <| pkg.dir / "c" / "text_host.c"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString]
  buildO (pkg.buildDir / "c" / "text_host.o") src weakArgs #["-O2", "-fPIC"] "cc"

/-- A weak stand-in for the claim commands' full initializer, so the host links apps that
`meta import` them without libLean (see lean/c/claims_meta.c). `bin/cairn-link` adds it to every
library it merges, whichever package the app is in. Not in `Cairn`'s own library: Lake
executables that load modules at run time (`ledger`, `claims`) would find the stub and call it. -/
target claims_meta.o pkg : System.FilePath := do
  let src ← inputTextFile <| pkg.dir / "c" / "claims_meta.c"
  let args := #["-I", (← getLeanIncludeDir).toString]
  buildO (pkg.buildDir / "c" / "claims_meta.o") src args #["-O2", "-fPIC"] "cc"

/-! Cairn's own libraries (docs/packages-and-std.md, "The layout"). Module names are unchanged;
only which library a module is built and archived in is. Lake gives a module to the *last*
library declared that matches it, and a root also matches its submodules (`Cairn.Frame` matches
`Cairn.Frame.Layout`). So the libraries after `Cairn` take back the proofs, tests and tools under
its roots, and the umbrella modules (`Cairn`, `CairnAll`, `Cairn.Layout`, `Cairn.Runtime`,
`Cairn.Claims`, `Cairn.Fuzz`) are only `globs`, never `roots`, so they claim nothing beneath them.
Two umbrellas: `Cairn` (`Cairn.lean`) imports the `Cairn` library and is in it, so it is what apps
`import` and link; `CairnAll` imports everything but the tools and the fuzzer, and is what the
ledger, the audit, the kernel replay and `make doc` read. -/

/-- The linked closure: everything `bin/cairn-link` (`@cairn/Cairn:static`) puts in an app. No
`import Lean`, no proofs. `Cairn.Abi` is its top (the host runs `initialize_cairn_Cairn_Abi`);
`Cairn.Fuzz.Rng` is here because app modules name its `Custom` hook. The old names of moved
modules stay until 0.2.0, since apps import them. The `Cairn` umbrella imports each of these. -/
def linked : Array Lean.Name := #[`Cairn.Geometry, `Cairn.Claim, `Cairn.Effects, `Cairn.Font, `Cairn.Input,
    `Cairn.UI.Node, `Cairn.UI.Images, `Cairn.UI.Grid, `Cairn.UI.Hit, `Cairn.Surface, `Cairn.App,
    `Cairn.Claims.Move, `Cairn.Claims.Machine, `Cairn.Claims.Core,
    `Cairn.Text.Wrap, `Cairn.Text.Field, `Cairn.Text.Host, `Cairn.Layout.Core, `Cairn.Layout.Facts,
    `Cairn.Runtime.World, `Cairn.Runtime.Step, `Cairn.Runtime.Abi,
    `Cairn.Frame, `Cairn.Frame.Bytes, `Cairn.Frame.Encode, `Cairn.Frame.Events, `Cairn.Frame.Menu,
    `Cairn.Frame.Build, `Cairn.Abi, `Cairn.Fuzz.Rng,
    `Cairn.Frame.Boundary, `Cairn.Runtime.Hit, `Cairn.Text.Metrics]

@[default_target]
lean_lib Cairn where
  roots := linked
  globs := linked.map .one ++ #[.one `Cairn]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[text_host.o]

def proofs : Array Lean.Name := #[`Cairn.Text.Proofs, `Cairn.Text.WrapProofs, `Cairn.Text.FieldTests,
    `Cairn.Layout.Proofs, `Cairn.Layout.Bridge, `Cairn.Layout.Check, `Cairn.Layout.Rigid,
    `Cairn.Layout.Para, `Cairn.Layout.Grid, `Cairn.Layout.Tests,
    `Cairn.Runtime.Proofs, `Cairn.Runtime.WorldProofs, `Cairn.Runtime.InFlight,
    `Cairn.Claims.Deliver,
    `Cairn.Frame.Layout, `Cairn.Frame.EventsTests, `Cairn.Frame.BuildTests, `Cairn.Abi.Tests]

/-- Proofs and tests about `Cairn`'s code, and the umbrellas that import them (`CairnAll`). Never
linked. -/
@[default_target]
lean_lib CairnProofs where
  roots := proofs
  globs := proofs.map .one ++ #[.one `CairnAll, .one `Cairn.Layout, .one `Cairn.Runtime]

/-- The claim commands. Apps `meta import` `Cairn.Claims.Elab`, so it runs at compile time only
(`import Lean`; docs/claims.md, "Linking"). -/
@[default_target]
lean_lib CairnClaims where
  roots := #[`Cairn.Claims.Elab, `Cairn.Claims.Registry]
  globs := #[.one `Cairn.Claims.Elab, .one `Cairn.Claims.Registry, .one `Cairn.Claims]

/-- Tests for the claim commands. Not imported by `CairnAll`, so their ids stay out of the ledger. -/
@[default_target]
lean_lib ClaimsTests where
  roots := #[`Cairn.Claims.Tests]

/-- The trusted base's `assume` claims (`Cairn.Fuzz.Trusted.Claims`). They use the claim commands
(`import Lean` at compile time), so they stay out of `Cairn`, which the host links; the ledger
reads them as a root. -/
@[default_target]
lean_lib CairnTrusted where
  roots := #[`Cairn.Fuzz.Trusted.Claims]

/-- The ledger, claim and doc export, and the axiom audit, behind the `lean_exe`s below. Not a
default target: `make kernel` replays the default targets in one environment, and each of these
defines a root `main`. -/
lean_lib CairnTools where
  roots := #[`Cairn.Claims.Tool, `Cairn.Claims.Ledger, `Cairn.Claims.LedgerTests,
    `Cairn.Claims.Export, `Cairn.Claims.Release, `Cairn.Doc.Export, `Audit]

/-- `lake exe ledger check|update`: guards `claims.lock` (see docs/claims.md). -/
lean_exe ledger where
  root := `Cairn.Claims.Ledger
  supportInterpreter := true

/-- `lake exe claims <Module>…`: every claim as JSON, for the map. -/
lean_exe claims where
  root := `Cairn.Claims.Export
  supportInterpreter := true

/-- `lake exe doc [--check] <Module>…`: modules, declarations, signatures and doc comments as JSON,
for `make doc` (docs/doc.md); `--check` runs the doc tests. -/
lean_exe doc where
  root := `Cairn.Doc.Export
  supportInterpreter := true

lean_exe bench where
  root := `Bench

lean_exe audit where
  root := `Audit
  supportInterpreter := true

lean_exe framecorpus where
  root := `FrameCorpus

/-- The conformance generator (tools/conformance, docs/conformance.md): walks an app's model and
writes move sequences with the frames the app must show. Each app has an entry-point module of
its own (an app package's `<App>.Conformance`), which `cairn conformance` links with that app's
library and the host's Core Text metrics. Never linked into the host. -/
@[default_target]
lean_lib Conformance where
  srcDir := "../tools/conformance/lean"
  globs := #[.submodules `Conformance]

/-- The fuzzer (docs/fuzz.md): generators, the walk, the checks and shrinking, and the driver
behind `lake exe fuzz` (`import Lean`). Not linked into any host binary; its PRNG,
`Cairn.Fuzz.Rng`, is in `Cairn`. -/
@[default_target]
lean_lib CairnFuzz where
  roots := #[`Cairn.Fuzz.Metrics, `Cairn.Fuzz.Target, `Cairn.Fuzz.Text, `Cairn.Fuzz.Host,
    `Cairn.Fuzz.Walk, `Cairn.Fuzz.Shrink, `Cairn.Fuzz.Collect, `Cairn.Fuzz.Main,
    `Cairn.Fuzz.HostTests]
  globs := #[.one `Cairn.Fuzz.Metrics, .one `Cairn.Fuzz.Target, .one `Cairn.Fuzz.Text,
    .one `Cairn.Fuzz.Host, .one `Cairn.Fuzz.HostTests, .one `Cairn.Fuzz.Walk, .one `Cairn.Fuzz.Shrink, .one `Cairn.Fuzz.Collect, .one `Cairn.Fuzz.Main,
    .one `Cairn.Fuzz]

/-- Lean's side of the trusted-base fuzzer (docs/fuzz.md, "Trusted base"): generators, the
proved decoders' verdicts and a one-field app, exported over C for the Swift executable
`cairn-fuzz-trusted`, which links this next to `libcairn_lean.a`. No `import Lean`. It carries
`Cairn.Frame.Dump` (the canonical dump, which no app links); `Cairn.Fuzz.Rng` comes from
`libcairn_lean.a`. -/
@[default_target]
lean_lib TrustedFuzz where
  roots := #[`Cairn.Fuzz.Trusted.Export]
  globs := #[.one `Cairn.Fuzz.Trusted.Export, .one `Cairn.Fuzz.Trusted.Gen, .one `Cairn.Frame.Dump]
  defaultFacets := #[LeanLib.staticFacet]
