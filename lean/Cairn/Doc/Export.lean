import Lean
import Cairn.Claims.Tool

/-! `lake exe doc [--check] <Module>…`: the API half of `cairn doc` (docs/doc.md), as JSON.

Imports the given modules (built `.olean`s) and writes, for every module whose name starts with
one of them: its module doc comments and imports, and every declaration it makes that a reader
would look up: its kind, its signature (pretty-printed, with the constants in it tagged so the
pages can link them), its doc comment, its line, whether it is private, a structure's fields, an
inductive type's constructors, the class and types of an instance, and the extra axioms of a
theorem (beyond `propext`, `Classical.choice` and `Quot.sound`). Generated plumbing (recursors,
`noConfusion`, matchers, equation lemmas, structure projections, which appear as fields) is left
out.

The claims half comes from `lake exe claims`; `tools/doc/cairn-doc.ts` joins the two.

With `--check`, Lean code blocks in doc comments are doc tests: each is elaborated in an
environment with the documented modules imported, inside the namespace of the declaration (or
module) it documents, and any error is reported on stderr with the block's source line. The exit
code is 1 if one fails. A block fenced ` ```lean ignore ` is shown and not checked. -/

namespace Cairn.Doc
open Lean Meta Widget

/-- Where a module's source is, relative to the repository root. -/
def fileOf (m : Name) : String :=
  "lean/" ++ "/".intercalate (m.components.map (·.toString)) ++ ".lean"

/-- A pretty-printed term as segments: a string, or `[text, constant]` where the text names a
constant, so the pages can link it. -/
partial def segments (env : Environment) (infos : SubExpr.PosMap Elab.Info) :
    TaggedText (Nat × Nat) → Array Json
  | .text s => #[Json.str s]
  | .append as => as.foldl (fun acc a => acc ++ segments env infos a) #[]
  | .tag (n, _) a =>
    match infos.get? n with
    | some (.ofTermInfo ti) =>
      match ti.expr.consumeMData with
      | .const c _ =>
        let m := match env.getModuleIdxFor? c with
          | some i => env.header.moduleNames[i.toNat]!.toString
          | none => ""
        #[Json.arr #[Json.str a.stripTags, Json.str (privateToUserName c).toString, Json.str m]]
      | _ => segments env infos a
    | _ => segments env infos a

def width : Nat := 92

def render (f : FormatWithInfos) : MetaM Json :=
  return Json.arr (segments (← getEnv) f.infos (TaggedText.prettyTagged f.fmt (w := width)))

def signature (n : Name) : MetaM Json := do render (← PrettyPrinter.ppSignature n)

/-- A claim's formal statement, one of its `statementDecls`: the binders of the definition and
its body, so `post s s' := s'.count = 0` reads as written. -/
def statement (n : Name) : MetaM Json := do
  let some ci := (← getEnv).find? n | return Json.null
  let some v := ci.value? (allowOpaque := true) | return Json.mkObj [("sig", ← signature n)]
  lambdaTelescope v fun xs body => do
    let bs ← xs.mapM fun x => return toString (← x.fvarId!.getUserName)
    return Json.mkObj [("binders", toJson bs), ("body", ← render (← PrettyPrinter.ppExprWithInfos body))]

/-- The type of a structure field, with the structure's parameters and `self` as free variables. -/
def fieldType (proj : Name) : MetaM Json := do
  let ci ← getConstInfo proj
  forallTelescope ci.type fun _ body => do render (← PrettyPrinter.ppExprWithInfos body)

/-- Plumbing a reader never looks up. -/
def generated (env : Environment) (n : Name) : Bool :=
  isAuxRecursor env n || isNoConfusion env n || isRecCore env n || isMatcherCore env n ||
  (n.getPrefix != .anonymous && isStructure env n.getPrefix &&
    (getStructureFields env n.getPrefix).contains (Name.mkSimple n.getString!)) ||
  (match env.find? n with | some (.ctorInfo _) => true | _ => false) ||
  -- The methods of a derived or written instance (`instReprTodo.repr`) are part of it.
  (n.getPrefix != .anonymous && isInstanceCore env n.getPrefix) ||
  match n with
  | .str _ s => s.startsWith "eq_" || s == "eq_def" || s.startsWith "proof_" || s.startsWith "match_" ||
      s == "sizeOf_spec" || s == "inj" || s == "injEq" || s == "ctorIdx" || s == "toCtorIdx" ||
      s.startsWith "_" || s == "induct" || s == "mutual_induct" || s == "below" || s == "brecOn"
  | _ => false

def kindOf (env : Environment) (n : Name) : ConstantInfo → String
  | .inductInfo _ => if isClass env n then "class" else if isStructure env n then "structure" else "inductive"
  | .defnInfo _ =>
    if isInstanceCore env n then "instance"
    else if getReducibilityStatusCore env n == .reducible then "abbrev" else "def"
  | .thmInfo _ => "theorem"
  | .opaqueInfo _ => if isInstanceCore env n then "instance" else "opaque"
  | .axiomInfo _ => "axiom"
  | .quotInfo _ => "def"
  | .ctorInfo _ => "constructor"
  | .recInfo _ => "recursor"

def docOf (env : Environment) (n : Name) : IO Json := do
  return match ← findDocString? env n (includeBuiltin := false) with
    | some d => Json.str d
    | none => Json.null

/-- An instance's class and the constants at the head of its arguments, so a type's page can
list the instances for it. -/
def instanceOf (ci : ConstantInfo) : MetaM Json :=
  forallTelescopeReducing ci.type fun _ body => do
    let cls := body.getAppFn.constName?.map (·.toString)
    let heads := body.getAppArgs.filterMap fun a => a.getAppFn.constName?.map (·.toString)
    return Json.mkObj [("class", toJson cls), ("for", toJson heads)]

def declJson (env : Environment) (m : Name) (n : Name) (ci : ConstantInfo) (line : Nat) : MetaM Json := do
  let kind := kindOf env n ci
  let mut fields := #[]
  let mut ctors := #[]
  if isStructure env n then
    for f in getStructureFields env n do
      let proj := n ++ f
      if env.contains proj then
        fields := fields.push (Json.mkObj [("name", f.toString), ("type", ← fieldType proj),
          ("doc", ← docOf env proj)])
  else if let .inductInfo i := ci then
    for c in i.ctors do
      ctors := ctors.push (Json.mkObj [("name", (privateToUserName c).toString),
        ("sig", ← signature c), ("doc", ← docOf env c)])
  let axioms : Json ← if kind == "theorem" then
      pure (toJson ((← Cairn.Claims.Tool.extraAxioms env n).map (·.toString)))
    else pure Json.null
  return Json.mkObj [
    ("name", (privateToUserName n).toString), ("kind", kind), ("module", m.toString),
    ("line", line), ("private", isPrivateName n),
    ("sig", ← signature n), ("doc", ← docOf env n),
    ("fields", Json.arr fields), ("ctors", Json.arr ctors),
    ("instance", ← if kind == "instance" then instanceOf ci else pure Json.null),
    ("axioms", axioms)]

/-! ### Doc tests -/

/-- The ` ```lean ` blocks of a doc comment: the line in the comment each starts on, and its
code. ` ```lean ignore ` and other languages are skipped. -/
def leanBlocks (doc : String) : Array (Nat × String) := Id.run do
  let mut out := #[]
  let mut cur : Option (Nat × Array String) := none
  let lines := (doc.splitOn "\n").toArray
  for h : i in [0:lines.size] do
    let l := lines[i].trimAscii.toString
    match cur with
    | none => if l == "```lean" then cur := some (i + 1, #[])
    | some (start, acc) =>
      if l == "```" then
        out := out.push (start, "\n".intercalate acc.toList)
        cur := none
      else cur := some (start, acc.push lines[i])
  return out

/-- Elaborate one block inside `ns`; the errors, if any. -/
def runBlock (env : Environment) (ns : Name) (code : String) : IO (Array (Nat × String)) := do
  let pre := if ns.isAnonymous then "" else s!"namespace {ns}\n"
  let post := if ns.isAnonymous then "" else s!"\nend {ns}"
  let opts := Options.empty |>.setBool `autoImplicit false |>.setBool `relaxedAutoImplicit false
  let (_, msgs) ← Elab.process (pre ++ code ++ post) env opts (fileName := "<doc test>")
  let errs := msgs.toList.filter (·.severity == .error)
  errs.toArray.mapM fun msg => do
    return (msg.pos.line - (if ns.isAnonymous then 1 else 2), ← msg.data.toString)

structure Test where
  file : String
  line : Nat
  ns : Name
  code : String

unsafe def main (args : List String) : IO UInt32 := do
  let check := args.contains "--check"
  let mods := (args.filter (· != "--check")).map String.toName
  if mods.isEmpty then
    IO.eprintln "usage: lake exe doc [--check] <Module>…   (e.g. Examples.Todo)"
    return 2
  let env ← Cairn.Claims.Tool.load mods
  let ours (m : Name) := mods.any (·.isPrefixOf m)
  let documented := env.header.moduleNames.filter ours
  -- `open Cairn`, so signatures say `Layout.Node` rather than `Cairn.Layout.Node`.
  let core : Core.Context :=
    { fileName := "doc", fileMap := default, maxHeartbeats := 0, openDecls := [.simple `Cairn []] }
  -- Declarations, by module, with the line each starts on.
  -- (the line the declaration, with its doc comment, starts on; the line of its name)
  let mut byModule : Std.HashMap Name (Array (Nat × Nat × Name × ConstantInfo)) := {}
  for (n, ci) in env.constants.map₁.toList do
    let some idx := env.getModuleIdxFor? n | continue
    let m := env.header.moduleNames[idx.toNat]!
    unless ours m do continue
    if generated env n then continue
    if n.isInternalDetail && !isPrivateName n then continue
    if let some p := privateToUserName? n then if p.isInternalDetail then continue
    let some r ← (findDeclarationRanges? n : CoreM _).toIO' core { env } | continue
    byModule := byModule.insert m ((byModule.getD m #[]).push (r.range.pos.line, r.selectionRange.pos.line, n, ci))
  let mut modules := #[]
  let mut decls := #[]
  let mut tests : Array Test := #[]
  for m in documented do
    let docs := (getModuleDoc? env m).getD #[]
    let file := fileOf m
    for d in docs do
      for (l, code) in leanBlocks d.doc do
        tests := tests.push { file, line := d.declarationRange.pos.line + l, ns := m, code }
    let imports : Array String := match env.getModuleIdx? m with
      | some idx => env.header.moduleData[idx.toNat]!.imports.map (fun (i : Import) => i.module.toString)
      | none => #[]
    modules := modules.push (Json.mkObj [("name", m.toString), ("file", file),
      ("docs", Json.arr (docs.map fun d => Json.mkObj [("doc", d.doc),
        ("line", d.declarationRange.pos.line)])),
      ("imports", toJson imports)])
    let ds := (byModule.getD m #[]).qsort (fun a b => a.1 < b.1)
    for (start, line, n, ci) in ds do
      let ns := (privateToUserName n).getPrefix
      let ctx := { core with currNamespace := ns }
      let j ← try ((declJson env m n ci line).run' {} : CoreM _).toIO' ctx { env }
        catch e => do
          IO.eprintln s!"doc: {n}: {e}"
          continue
      decls := decls.push j
      if let some d ← findDocString? env n (includeBuiltin := false) then
        for (l, code) in leanBlocks d do
          tests := tests.push { file, line := start + l, ns, code }
  -- Each claim's formal statement, by declaration.
  let mut statements := #[]
  for e in Cairn.Claims.allEntries env do
    unless ours e.module do continue
    for n in e.statement do
      let ctx := { core with currNamespace := n.getPrefix }
      try
        let j ← ((statement n).run' {} : CoreM _).toIO' ctx { env }
        statements := statements.push (n.toString, j)
      catch e => IO.eprintln s!"doc: {n}: {e}"
  let mut failed : Nat := 0
  if check then
    for t in tests do
      let errs ← runBlock env t.ns t.code
      unless errs.isEmpty do
        failed := failed + 1
        for (l, e) in errs do IO.eprintln s!"doc test failed: {t.file}:{t.line + l}: {e}"
    IO.eprintln s!"doc tests: {tests.size} blocks, {failed} failed"
  IO.println (Json.mkObj [("roots", toJson (mods.map (·.toString))),
    ("modules", Json.arr modules), ("decls", Json.arr decls),
    ("statements", Json.mkObj statements.toList),
    ("doctests", Json.mkObj [("checked", check), ("blocks", tests.size), ("failed", toJson failed)])]).compress
  return if failed == 0 then 0 else 1

end Cairn.Doc

unsafe def main (args : List String) : IO UInt32 := Cairn.Doc.main args
