import Lean
import Cairn.Claims.Registry
import Cairn.Fuzz.Target

/-! # `fuzz_targets%`: every fuzzable app, found at compile time

Elaborates to a `List Cairn.Fuzz.Target`, one per `Machine` declared in an app module (`appModule`: `Examples`, or an app package's own) of
the imported environment. For each machine it collects, from the claim registry and the
environment:

- the `App` of the same state type declared in the machine's module (preferring `<ns>.app`);
- the keyed moves of the machine's namespace;
- the invariants stated against it, with their `check` when `invariant` generated one;
- every claim the module declares;
- `<ns>.fuzz : Cairn.Fuzz.Custom S`, if the app defines one.

So an app needs no fuzz code: importing it from `Examples.lean` is enough. Compile time only
(imports `Lean`); the `fuzz` executable is the only thing that uses it. -/

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

/-- Modules that hold apps: anything but Cairn itself and Lean's libraries. In this repository
that is `Examples`; in an app's package, the app's own modules (`Yap.*`). -/
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

elab "fuzz_targets%" : term => do
  let env ← getEnv
  let entries := allEntries env
  let machines := (constsOfType env ``Cairn.Claims.Machine).qsort (·.1.toString < ·.1.toString)
  let apps := constsOfType env ``Cairn.App
  let mut targets : Array Term := #[]
  for (mName, mInfo) in machines do
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
    let sameModule := machines.filter fun (n, _) => moduleOf env n == some mod
    let name := last mod ++
      (if sameModule.size > 1 then "." ++ last mName else "")
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
      name := $(quote name), module := $(quote mod.toString), ns := $(quote ns.toString),
      machineDecl := $(quote (rel ns mName)), appDecl := $appDeclT,
      S := Cairn.Claims.StateOf $mId, machine := $mId, app := $appT,
      keyed := [$keyedT,*], invariants := [$invTerms,*], claims := [$claimT,*],
      custom := $customT } : Cairn.Fuzz.Target)))
  elabTerm (← `([$targets,*])) (some (mkApp (mkConst ``List [Level.one]) (mkConst ``Cairn.Fuzz.Target)))

end Cairn.Fuzz.Collect
