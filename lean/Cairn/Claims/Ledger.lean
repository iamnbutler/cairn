import Cairn.Claims.Tool

/-! `lake exe ledger check|update [--accept] [--lock PATH] [--root MODULE]…`

`claims.lock` records every claim id ever issued: one line per id with its kind, whether it is
retired, a hash of its formal statement and its title. Ids are the contract, so:

- `check` fails when a locked id is missing from the code (unless the lock says it is retired),
  when an id is reused for a different kind, when a retired id comes back, when the code issues
  an id twice, when a claim has no description, and when the code has an id the lock doesn't
  (run `update`). It warns when a claim's formal statement or title changed: give it a new id,
  or `update --accept` if the meaning is the same.
- `update` appends new ids, marks newly retired ones, and with `--accept` records changed
  hashes and titles. It never removes a line, and refuses while `check` has errors other than
  new ids.

The code's claims are those reachable by importing the roots (`Cairn` and `Examples` by
default). -/

namespace Cairn.Claims.Ledger
open Lean Cairn.Claims Cairn.Claims.Tool

structure Line where
  id : ClaimId
  kind : ClaimKind
  retired : Bool
  hash : String
  title : String

def header : String :=
  "# claims.lock: every claim id ever issued. Written by `lake exe ledger update`; never edit by hand.\n" ++
  "# id\tkind\tstatus\tstatement\ttitle\n"

def Line.render (l : Line) : String :=
  s!"{l.id}\t{l.kind.name}\t{if l.retired then "retired" else "active"}\t{l.hash}\t{l.title}"

def parse (text : String) : Except String (Array Line) := do
  let mut out := #[]
  let mut n := 0
  for raw in text.splitOn "\n" do
    n := n + 1
    let s := raw.trimAscii.toString
    if s.isEmpty || s.startsWith "#" then continue
    match raw.splitOn "\t" with
    | [id, kind, status, hash, title] =>
      let some id := id.toNat? | throw s!"claims.lock:{n}: bad id `{id}`"
      let some kind := ClaimKind.ofName? kind | throw s!"claims.lock:{n}: bad kind `{kind}`"
      unless status == "active" || status == "retired" do
        throw s!"claims.lock:{n}: bad status `{status}`"
      out := out.push { id, kind, retired := status == "retired", hash, title }
    | _ => throw s!"claims.lock:{n}: expected 5 tab-separated fields"
  return out

def render (ls : Array Line) : String :=
  header ++ String.intercalate "\n" ((ls.qsort (·.id < ·.id)).map Line.render).toList ++ "\n"

structure Report where
  errors : Array String := #[]
  warnings : Array String := #[]
  /-- Errors that `update` resolves (new ids). -/
  fresh : Array String := #[]

def Report.err (r : Report) (m : String) : Report := { r with errors := r.errors.push m }
def Report.warn (r : Report) (m : String) : Report := { r with warnings := r.warnings.push m }
def Report.new (r : Report) (m : String) : Report := { r with fresh := r.fresh.push m }

def lineOf (env : Environment) (e : Entry) : Line :=
  { id := e.info.id, kind := e.info.kind, retired := e.info.retired.isSome
    hash := statementHash env e, title := e.info.title }

def compare (env : Environment) (locked : Array Line) : Report := Id.run do
  let mut r : Report := {}
  for (a, b) in clashes env do
    r := r.err s!"^{a.info.id} is issued twice: {a.label} and {b.label}"
  let code := entries env
  let byId : Std.HashMap ClaimId Entry := code.foldl (fun m e => m.insert e.info.id e) {}
  for l in locked do
    match byId[l.id]? with
    | none =>
      unless l.retired do
        r := r.err s!"^{l.id} {l.kind.name} “{l.title}” is in claims.lock but gone from the code. Ids never disappear: retire it with `retire ^{l.id} {l.kind.name} \"{l.title}\" because \"…\"`"
    | some e =>
      if e.info.kind != l.kind then
        r := r.err s!"^{l.id} was issued as a {l.kind.name} (“{l.title}”) and is now reused as a claim of kind `{e.info.kind.name}`: {e.label}. Take a new id"
      else if l.retired && e.info.retired.isNone then
        r := r.err s!"^{l.id} “{l.title}” is retired and has come back: {e.label}. Take a new id"
      else if e.info.retired.isNone then
        let h := statementHash env e
        if h != l.hash then
          r := r.warn s!"^{l.id} “{e.info.title}”: meaning changed (statement {l.hash} → {h}): give it a new id or `lake exe ledger update --accept`"
        if e.info.title != l.title then
          r := r.warn s!"^{l.id}: title changed from “{l.title}” to “{e.info.title}”; `lake exe ledger update --accept` records it"
  let lockedIds : Std.HashSet ClaimId := locked.foldl (fun s l => s.insert l.id) {}
  for e in code do
    unless lockedIds.contains e.info.id do
      r := r.new s!"{e.label} is not in claims.lock: run `lake exe ledger update`"
    if e.info.retired.isNone && e.info.does.trimAscii.isEmpty then
      r := r.err s!"{e.label} has no description (`does`)"
  return r

def update (env : Environment) (locked : Array Line) (accept : Bool) : Array Line := Id.run do
  let code := entries env
  let byId : Std.HashMap ClaimId Entry := code.foldl (fun m e => m.insert e.info.id e) {}
  let mut out := #[]
  for l in locked do
    match byId[l.id]? with
    | some e =>
      if e.info.kind == l.kind then
        if e.info.retired.isSome then
          out := out.push { l with retired := true }
        else if accept then
          out := out.push { lineOf env e with retired := l.retired }
        else out := out.push l
      else out := out.push l
    | none => out := out.push l
  let lockedIds : Std.HashSet ClaimId := locked.foldl (fun s l => s.insert l.id) {}
  for e in code do
    unless lockedIds.contains e.info.id do out := out.push (lineOf env e)
  return out

def defaultLock : IO System.FilePath := do
  if ← System.FilePath.pathExists "lakefile.lean" then return "../claims.lock"
  return "claims.lock"

def usage : String :=
  "usage: lake exe ledger (check | update [--accept]) [--lock PATH] [--root MODULE]…"

unsafe def main (args : List String) : IO UInt32 := do
  let mut cmd := none
  let mut accept := false
  let mut lock ← defaultLock
  let mut roots : List Name := []
  let mut rest := args
  while !rest.isEmpty do
    match rest with
    | "--accept" :: r => accept := true; rest := r
    | "--lock" :: p :: r => lock := p; rest := r
    | "--root" :: m :: r => roots := roots ++ [m.toName]; rest := r
    | c :: r => if cmd.isNone then cmd := some c; rest := r else
        IO.eprintln usage; return 2
    | [] => rest := []
  if roots.isEmpty then roots := [`Cairn, `Examples]
  let env ← load roots
  let text ← if ← lock.pathExists then IO.FS.readFile lock else pure ""
  let locked ← match parse text with
    | .ok ls => pure ls
    | .error e => IO.eprintln s!"ledger: {e}"; return 1
  let r := compare env locked
  for w in r.warnings do IO.eprintln s!"ledger: warning: {w}"
  match cmd with
  | some "check" =>
    for e in r.errors ++ r.fresh do IO.eprintln s!"ledger: error: {e}"
    let n := (entries env).size
    IO.println s!"ledger: {n} claims in code, {locked.size} in {lock}, {r.errors.size + r.fresh.size} errors, {r.warnings.size} warnings"
    return if r.errors.isEmpty && r.fresh.isEmpty then 0 else 1
  | some "update" =>
    unless r.errors.isEmpty do
      for e in r.errors do IO.eprintln s!"ledger: error: {e}"
      IO.eprintln "ledger: not updating claims.lock until these are fixed"
      return 1
    let out := update env locked accept
    IO.FS.writeFile lock (render out)
    IO.println s!"ledger: wrote {out.size} ids to {lock} ({out.size - locked.size} new)"
    return 0
  | _ => IO.eprintln usage; return 2

end Cairn.Claims.Ledger

unsafe def main (args : List String) : IO UInt32 := Cairn.Claims.Ledger.main args
