import Cairn.Claims.Tool
import Cairn.Claims.Release

/-! `lake exe ledger check|update [--accept] [--lock PATH] [--root MODULE]…`

`claims.lock` records every claim id ever issued: one line per id with its kind, whether it is
retired, a hash of its formal statement and its title. Ids are the contract, so:

- `check` fails when a locked id is missing from the code (unless the lock says it is retired),
  when an id is reused for a different kind, when a retired id comes back, when the code issues
  an id twice, when a claim has no description, and when the code has an id the lock doesn't or
  retires one the lock still has as active (run `update` for both). It warns when a claim's formal statement or title changed: give it a new id,
  or `update --accept` if the meaning is the same.
- `check` and `update` also fail when the code retires a claim, or the lock marks it moved, that
  the package's last release had active, unless `cairn.toml`'s version is a breaking one after that
  release: a new major version, or a new minor version while at 0.x (`Cairn.Claims.Release`). The
  release is the highest final `v<version>` tag that isn't after the current version, and its
  `claims.lock` comes from git. With no `cairn.toml` beside the lock, or no tag, there's nothing
  to check. `--version V` stands in for `cairn.toml`'s version.
- `move <scope> <id>…` marks ids that left this package for another as `moved:<scope>`: they must
  be in the lock and gone from this scope's code.
- `update` appends new ids, marks newly retired ones, and with `--accept` records changed
  hashes and titles. It never removes a line, and refuses while `check` has errors other than
  new ids.

The code's claims are those reachable by importing the roots (`CairnAll`, `Examples` and
`Cairn.Fuzz.Trusted.Claims`, the trusted base's assumptions, by default) and declared in one
package scope (`--scope`, default `cairn`; see `cairn.claims.scope`). Each package keeps its own
`claims.lock` for its own scope: an app's ledger never reads Cairn's ids, and Cairn's never reads
the app's.

A claim that moves to another package keeps its number there and is marked `moved:<scope>` in
the lock it left (Yap's ids, `moved:yap`, after Yap moved to its own repository): the id stays
issued in the old scope, and can't come back in it. -/

namespace Cairn.Claims.Ledger
open Lean Cairn.Claims Cairn.Claims.Tool

structure Line where
  id : ClaimId
  kind : ClaimKind
  retired : Bool
  hash : String
  title : String
  /-- The scope the claim moved to, if it left this package (`moved:yap`). -/
  moved : Option String := none
deriving Inhabited

def header : String :=
  "# claims.lock: every claim id ever issued. Written by `lake exe ledger update`; never edit by hand.\n" ++
  "# id\tkind\tstatus\tstatement\ttitle\n"

def Line.status (l : Line) : String :=
  match l.moved with
  | some to => s!"moved:{to}"
  | none => if l.retired then "retired" else "active"

def Line.render (l : Line) : String :=
  s!"{l.id}\t{l.kind.name}\t{l.status}\t{l.hash}\t{l.title}"

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
      let moved := if status.startsWith "moved:" then some (status.drop 6).toString else none
      unless status == "active" || status == "retired" || moved.any (!·.isEmpty) do
        throw s!"claims.lock:{n}: bad status `{status}`"
      out := out.push { id, kind, retired := status == "retired", hash, title, moved }
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

/-- The claims of one scope. -/
def inScope (env : Environment) (scope : String) : Array Entry :=
  (entries env).filter (·.scope == scope)

def compare (env : Environment) (scope : String) (locked : Array Line) : Report := Id.run do
  let mut r : Report := {}
  for (a, b) in clashes env do
    if a.scope == scope then
      r := r.err s!"{a.ref} is issued twice: {a.label} and {b.label}"
  let code := inScope env scope
  let byId : Std.HashMap ClaimId Entry := code.foldl (fun m e => m.insert e.info.id e) {}
  for l in locked do
    match byId[l.id]? with
    | none =>
      unless l.retired || l.moved.isSome do
        r := r.err s!"^{l.id} {l.kind.name} “{l.title}” is in claims.lock but gone from the code. Ids never disappear: retire it with `retire ^{l.id} {l.kind.name} \"{l.title}\" because \"…\"`"
    | some e =>
      if let some to := l.moved then
        r := r.err s!"^{l.id} “{l.title}” moved to {to}^{l.id} and has come back: {e.label}. Take a new id"
      else if e.info.kind != l.kind then
        r := r.err s!"^{l.id} was issued as a {l.kind.name} (“{l.title}”) and is now reused as a claim of kind `{e.info.kind.name}`: {e.label}. Take a new id"
      else if l.retired && e.info.retired.isNone then
        r := r.err s!"^{l.id} “{l.title}” is retired and has come back: {e.label}. Take a new id"
      else if !l.retired && e.info.retired.isSome then
        r := r.new s!"^{l.id} “{l.title}” is retired in the code but active in claims.lock: run `lake exe ledger update`"
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

def update (env : Environment) (scope : String) (locked : Array Line) (accept : Bool) :
    Array Line := Id.run do
  let code := inScope env scope
  let byId : Std.HashMap ClaimId Entry := code.foldl (fun m e => m.insert e.info.id e) {}
  let mut out := #[]
  for l in locked do
    match byId[l.id]? with
    | some e =>
      if l.moved.isNone && e.info.kind == l.kind then
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

/-- The ids of `scope` that have ended, retired in the code or retired or moved in the lock
(`locked`, before `update` writes it). -/
def ended (env : Environment) (scope : String) (locked : Array Line) : List ClaimId :=
  let code := inScope env scope
  let inCode := code.filterMap fun e => if e.info.retired.isSome then some e.info.id else none
  let inLock := locked.filterMap fun l =>
    if (l.retired || l.moved.isSome) && !code.any (·.info.id == l.id) then some l.id else none
  (inCode ++ inLock).toList

/-- The errors for ids retired without a breaking version (`Release.blocked`): `released` is the
last release and its ledger, `current` the version in `cairn.toml`. -/
def retirements (env : Environment) (scope : String) (locked : Array Line)
    (released : Release.Version) (before : Array Line) (current : Release.Version) : Array String :=
  let active := (before.filter fun l => !l.retired && l.moved.isNone).map (·.id)
  let blocked := Release.blocked released current active.toList (ended env scope locked)
  blocked.toArray.map fun id =>
    let title := (before.find? (·.id == id)).map (·.title) |>.getD ""
    s!"^{id} “{title}” was active in {released}, so retiring or moving it needs a new major version (a new minor version while at 0.x), not {current}: set version = \"{Release.needed released}\" or later in cairn.toml"

/-- The last release beside `lock`, from its git tags, and that release's `claims.lock`, for
`retirements`; `none` when there is no `cairn.toml` (and no `--version`) or no released tag. -/
def lastRelease (lock : System.FilePath) (version? : Option String) :
    IO (Option (Release.Version × Array Line × Release.Version)) := do
  let dir := lock.parent.getD "."
  let dir : System.FilePath := if dir.toString.isEmpty then "." else dir
  let version? ← match version? with
    | some v => pure (some v)
    | none =>
      let toml := dir / "cairn.toml"
      if ← toml.pathExists then pure (Release.manifestVersion? (← IO.FS.readFile toml)) else pure none
  let some text := version? | return none
  let some current := Release.Version.parse? text
    | throw <| IO.userError s!"`{text}` isn't a version like 0.1.0"
  let tags ← IO.Process.output { cmd := "git", args := #["tag", "--list", "v*"], cwd := dir }
  if tags.exitCode != 0 then return none
  let some released := Release.latest (tags.stdout.splitOn "\n") current | return none
  let name := lock.fileName.getD "claims.lock"
  let shown ← IO.Process.output
    { cmd := "git", args := #["show", s!"v{released}:./{name}"], cwd := dir }
  -- A release from before the package had a ledger promised no claims.
  if shown.exitCode != 0 then return some (released, #[], current)
  match parse shown.stdout with
  | .ok before => return some (released, before, current)
  | .error e => throw <| IO.userError s!"v{released}'s {e}"

def defaultLock : IO System.FilePath := do
  if ← System.FilePath.pathExists "lakefile.lean" then return "../claims.lock"
  return "claims.lock"

def usage : String :=
  "usage: lake exe ledger (check | update [--accept] | move <scope> <id>…) [--lock PATH] [--scope NAME] [--root MODULE]… [--version V]"

unsafe def main (args : List String) : IO UInt32 := do
  let mut cmd := none
  let mut accept := false
  let mut lock ← defaultLock
  let mut roots : List Name := []
  let mut scope := "cairn"
  let mut operands : List String := []
  let mut version : Option String := none
  let mut rest := args
  while !rest.isEmpty do
    match rest with
    | "--accept" :: r => accept := true; rest := r
    | "--lock" :: p :: r => lock := p; rest := r
    | "--root" :: m :: r => roots := roots ++ [m.toName]; rest := r
    | "--scope" :: s :: r => scope := s; rest := r
    | "--version" :: v :: r => version := some v; rest := r
    | c :: r => if cmd.isNone then cmd := some c; rest := r else
        if cmd == some "move" then operands := operands ++ [c]; rest := r else
        IO.eprintln usage; return 2
    | [] => rest := []
  if roots.isEmpty then roots := [`CairnAll, `Examples, `Cairn.Fuzz.Trusted.Claims]
  let env ← load roots
  let text ← if ← lock.pathExists then IO.FS.readFile lock else pure ""
  let locked ← match parse text with
    | .ok ls => pure ls
    | .error e => IO.eprintln s!"ledger: {e}"; return 1
  let mut r := compare env scope locked
  if cmd == some "check" || cmd == some "update" then
    match ← lastRelease lock version with
    | some (released, before, current) =>
      for e in retirements env scope locked released before current do r := r.err e
    | none => pure ()
  for w in r.warnings do IO.eprintln s!"ledger: warning: {w}"
  match cmd with
  | some "check" =>
    for e in r.errors ++ r.fresh do IO.eprintln s!"ledger: error: {e}"
    let n := (inScope env scope).size
    IO.println s!"ledger: {n} {scope} claims in code, {locked.size} in {lock}, {r.errors.size + r.fresh.size} errors, {r.warnings.size} warnings"
    return if r.errors.isEmpty && r.fresh.isEmpty then 0 else 1
  | some "update" =>
    unless r.errors.isEmpty do
      for e in r.errors do IO.eprintln s!"ledger: error: {e}"
      IO.eprintln "ledger: not updating claims.lock until these are fixed"
      return 1
    let out := update env scope locked accept
    IO.FS.writeFile lock (render out)
    IO.println s!"ledger: wrote {out.size} ids to {lock} ({out.size - locked.size} new)"
    return 0
  | some "move" =>
    let to :: ids := operands | IO.eprintln usage; return 2
    let code := inScope env scope
    let mut out := locked
    for i in ids do
      let some id := i.toNat? | IO.eprintln s!"ledger: `{i}` is not an id"; return 2
      let some k := out.findIdx? (·.id == id) | IO.eprintln s!"ledger: ^{id} is not in {lock}"; return 1
      if code.any (·.info.id == id) then
        IO.eprintln s!"ledger: ^{id} is still in {scope}'s code; move it out first"; return 1
      out := out.set! k { out[k]! with moved := some to }
    IO.FS.writeFile lock (render out)
    IO.println s!"ledger: marked {ids.length} ids moved:{to} in {lock}"
    return 0
  | _ => IO.eprintln usage; return 2

end Cairn.Claims.Ledger

unsafe def main (args : List String) : IO UInt32 := Cairn.Claims.Ledger.main args
