import Cairn.Claims.Tool

/-! `lake exe claims <Module>…`: the claims declared in the given modules (and their
submodules), as JSON, for the map.

Each claim has its id, kind, title, does, sees, place, module and declaration, the hash of its
formal statement, kind-specific facts (a move's triggers and keyedness, a flow's path through
moves, the machine a flow or invariant is about), and its evidence: each theorem's name and
whether it is proved from Lean's standard axioms only. -/

namespace Cairn.Claims.Export
open Lean Cairn.Claims Cairn.Claims.Tool

def evidenceJson (env : Environment) (role : String) (thm : Name) : IO Json := do
  let extra ← extraAxioms env thm
  return Json.mkObj [("role", role), ("theorem", thm.toString),
    ("proved", extra.isEmpty), ("extraAxioms", toJson (extra.map (·.toString)))]

/-- One step of a flow's witness, for drivers that replay it (the map's capture). -/
def actionJson : Cairn.Action → Json
  | .press c => step "press" c
  | .doublePress c => step "doublePress" c
  | .edit c op => (step "edit" c).setObjVal! "op" (opJson op)
  | .submit c => step "submit" c
  | .cancel c => step "cancel" c
  | .blur c => step "blur" c
where
  /-- `{"kind": "insert", "text": "milk"}`; operations without text are just their kind. -/
  opJson : Cairn.TextOp → Json
    | .insert s => Json.mkObj [("kind", "insert"), ("text", s)]
    | .paste s => Json.mkObj [("kind", "paste"), ("text", s)]
    | op => Json.mkObj [("kind", ((toString (repr op)).splitOn " ").head!.replace "Cairn.TextOp." "")]
  step (trigger : String) (c : Cairn.ControlRef) : Json :=
    Json.mkObj [("trigger", trigger), ("ref", c.label), ("claim", c.claim), ("key", c.key)]

/-- A flow's witness, evaluated from its generated `witness` definition. -/
unsafe def witnessJson (env : Environment) (e : Entry) : Json :=
  if e.info.kind != .flow then Json.null else
  match env.evalConst (List Cairn.Action) {} (e.decl ++ `witness) (checkMeta := false) with
  | .ok w => Json.arr (w.map actionJson).toArray
  | .error err => Json.mkObj [("error", err)]

/-- Where the claim is declared: the module's source file under `lean/`, and the line. -/
def posJson (env : Environment) (e : Entry) : IO Json := do
  let file := "lean/" ++ "/".intercalate (e.module.components.map (·.toString)) ++ ".lean"
  let ranges ← [e.decl, e.infoDecl].findSomeM? fun n => do
    let (r, _) ← (findDeclarationRanges? n : CoreM _).toIO { fileName := "claims", fileMap := default } { env }
    return r
  return Json.mkObj [("file", file),
    ("line", match ranges with | some r => toJson r.range.pos.line | none => Json.null)]

unsafe def claimJson (env : Environment) (e : Entry) : IO Json := do
  let ev ← e.evidence.mapM fun (r, n) => evidenceJson env r n
  let opt (o : Option String) : Json := match o with | some s => s | none => Json.null
  return Json.mkObj [
    ("id", e.info.id), ("ref", s!"^{e.info.id}"), ("kind", e.info.kind.name),
    ("title", e.info.title), ("does", e.info.does), ("sees", e.info.sees),
    ("place", match e.info.place with | some p => toJson p | none => Json.null),
    ("retired", opt e.info.retired),
    ("module", e.module.toString), ("decl", e.decl.toString),
    ("statement", statementHash env e),
    ("statementDecls", toJson (e.statement.map (·.toString))),
    ("triggers", toJson e.triggers), ("keyed", e.keyed),
    ("passes", toJson e.passes), ("witness", witnessJson env e),
    ("pos", ← posJson env e),
    ("machine", opt (e.machine.map (·.toString))),
    ("evidence", Json.arr ev)]

unsafe def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "usage: lake exe claims <Module>…   (e.g. Examples.Counter)"
    return 2
  let mods := args.map String.toName
  let env ← load mods
  let picked := (allEntries env).filter fun e => mods.any (·.isPrefixOf e.module)
  let cs ← picked.mapM (claimJson env)
  IO.println (Json.mkObj [("modules", toJson (mods.map (·.toString))), ("claims", Json.arr cs)]).pretty
  return 0

end Cairn.Claims.Export

unsafe def main (args : List String) : IO UInt32 := Cairn.Claims.Export.main args
