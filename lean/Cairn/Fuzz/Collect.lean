import Lean
import Lean.Compiler.ModPkgExt
import Cairn.Claims.Registry
import Cairn.Fuzz.Target

/-! # `fuzz_targets%`: every fuzzable app, found at compile time

Elaborates to a `List Cairn.Fuzz.Target`, one per `Machine` declared in an app module (`appModule`: an app package's own) of
the imported environment. For each machine it collects, from the claim registry and the
environment:

- the `App` of the same state type declared in the machine's module (preferring `<ns>.app`);
- the keyed moves of the machine's namespace;
- the invariants stated against it, with their `check` when `invariant` generated one;
- every claim the module declares;
- `<ns>.fuzz : Cairn.Fuzz.Custom S`, if the app defines one.

So an app needs no fuzz code: importing it from its `lean_exe fuzz` root is enough (Cairn's
test/fixture/lean/FuzzMain.lean). Compile time only
(imports `Lean`); the `fuzz` executable is the only thing that uses it.

**Whose machines.** A machine whose module is in the fuzz executable's own Lake package (the
package Lake builds the root in) is the package's: its target is named after its module's last
component (`Fixture`, `Claims`), with the machine's name added when the module declares several
(`Gallery.machine`). A machine of a dependency (cairn_atproto's session, imported by an app) is
collected too, marked `dependency`, and named with its package first: `cairn_atproto/Claims`.
`lake exe fuzz` runs only the package's own unless asked (`--deps`, docs/fuzz.md). Two targets
with one name are an error here, never one shadowing the other (cairn#221). -/

namespace Cairn.Fuzz.Collect
open Lean Elab Term Meta Cairn.Claims

/-- `n` relative to namespace `ns`, as source text. -/
def rel (ns n : Name) : String :=
  (n.replacePrefix ns .anonymous).toString

def last (n : Name) : String := match n with
  | .str _ s => s
  | _ => n.toString

def moduleOf (env : Environment) (n : Name) : Option Name :=
  env.getModuleIdxFor? n |>.map fun i => env.header.moduleNames[i.toNat]!

/-- Modules that hold apps: anything but Cairn itself and Lean's libraries, so an app package's
modules (`Fixture.*`, `Yap.*`) and its dependencies' (`CairnAtproto.*`). -/
def appModule (m : Name) : Bool :=
  ![`Cairn, `Init, `Std, `Lean, `Lake].contains m.getRoot

/-- Constants of app modules (`appModule`) whose type's head is `head`. -/
def constsOfType (env : Environment) (head : Name) : Array (Name × ConstantInfo) :=
  env.constants.fold (init := #[]) fun acc n ci =>
    if n.isInternal then acc else
    match moduleOf env n with
    | some m =>
      if appModule m && ci.type.getAppFn.constName? == some head then acc.push (n, ci)
      else acc
    | none => acc

/-- The Lake package of the module `m` was declared in (`fixture`, `cairn_atproto`), if Lake
named one; for the module being elaborated, its own. -/
def packageOf (env : Environment) (n : Name) : Option String :=
  match env.getModuleIdxFor? n with
  | some i => env.getModulePackageByIdx? i
  | none => env.getModulePackage?

/-- A machine as `fuzz_targets%` names it. -/
structure Found where
  machine : Name
  module : Name
  /-- Its Lake package, if Lake named one. -/
  package : Option String
  /-- How many machines its module declares. -/
  inModule : Nat

/-- The target names of `found`, in order, with whether each is a dependency's, for the fuzz
executable built in package `own`: a machine of `own` is named after its module's last component
(and the machine's, when its module has several); a dependency's has its package (or, if Lake
named none, its module's root) and `/` in front. A name given twice is an error naming both
machines. -/
def names (own : Option String) (found : Array Found) : Except String (Array (String × Bool)) := do
  let mut out : Array (String × Bool) := #[]
  let mut seen : Std.HashMap String Name := {}
  for f in found do
    let base := last f.module ++ (if f.inModule > 1 then "." ++ last f.machine else "")
    let dep := f.package != own
    let name := if dep then s!"{f.package.getD f.module.getRoot.toString}/{base}" else base
    if let some other := seen[name]? then
      throw s!"fuzz_targets%: two machines are both the target `{name}`: {other} and {f.machine}. \
        A target is named after its module's last component, so rename one of the modules (cairn#221)"
    seen := seen.insert name f.machine
    out := out.push (name, dep)
  return out

elab "fuzz_targets%" : term => do
  let env ← getEnv
  let entries := allEntries env
  let machines := (constsOfType env ``Cairn.Claims.Machine).qsort (·.1.toString < ·.1.toString)
  let apps := constsOfType env ``Cairn.App
  -- `constsOfType` keeps only constants with a module.
  let found := machines.map fun (mName, _) =>
    let mod := (moduleOf env mName).getD .anonymous
    { machine := mName, module := mod, package := packageOf env mName,
      inModule := (machines.filter fun (n, _) => moduleOf env n == some mod).size : Found }
  let named ← match names env.getModulePackage? found with
    | .ok ns => pure ns
    | .error e => throwError e
  let mut targets : Array Term := #[]
  for ((mName, mInfo), (name, dep)) in machines.zip named do
    let some mod := moduleOf env mName | continue
    let ns := mName.getPrefix
    let S := mInfo.type.appArg!
    -- The app over the same state, in the same module.
    let mut appName : Option Name := none
    for (aName, aInfo) in apps do
      if moduleOf env aName != some mod then continue
      if ← isDefEq aInfo.type.appArg! S then
        if appName.isNone || aName == ns ++ `app then appName := some aName
    let keyed := entries.filter fun e => e.info.kind == .move && e.ns == ns && e.keyed
    let invs := entries.filter fun e => e.info.kind == .invariant && e.machine == some mName
    let claims := entries.filter fun e => e.module == mod
    let pkg := (packageOf env mName).getD ""
    let mId := mkCIdent mName
    let invTerms ← invs.mapM fun e => do
      let check := e.decl ++ `check
      let checkT ← if env.contains check then `(some $(mkCIdent check)) else `(none)
      `({ info := $(mkCIdent e.infoDecl), decl := $(quote (rel ns e.decl)), check := $checkT })
    let appT ← match appName with
      | some a => `(some $(mkCIdent a))
      | none => `(none)
    let appDeclT ← match appName with
      | some a => `(some $(quote (rel ns a)))
      | none => `(none)
    let custom := ns ++ `fuzz
    let customT ← if env.contains custom then `($(mkCIdent custom)) else `({})
    let keyedT := keyed.map fun e => (quote e.info.id : Term)
    let claimT := claims.map fun e => (mkCIdent e.infoDecl : Term)
    targets := targets.push (← `(({
      name := $(quote name), module := $(quote mod.toString), package := $(quote pkg),
      dependency := $(quote dep), ns := $(quote ns.toString),
      machineDecl := $(quote (rel ns mName)), appDecl := $appDeclT,
      S := Cairn.Claims.StateOf $mId, machine := $mId, app := $appT,
      keyed := [$keyedT,*], invariants := [$invTerms,*], claims := [$claimT,*],
      custom := $customT } : Cairn.Fuzz.Target)))
  elabTerm (← `([$targets,*])) (some (mkApp (mkConst ``List [Level.one]) (mkConst ``Cairn.Fuzz.Target)))

end Cairn.Fuzz.Collect
