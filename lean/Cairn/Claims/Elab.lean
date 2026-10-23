module

public meta import Lean
public meta import Cairn.Claims.Core
public meta import Cairn.Claims.Registry

/-! The claim commands: `move`, `flow`, `invariant`, `assume`, `place` and `retire`, and the
`moves%` and `claims%` terms. See `docs/claims.md` for the syntax and what each check
guarantees.

Each command elaborates to ordinary declarations (definitions for the formal statement,
theorems for the evidence, a `ClaimInfo` and a value of the claim's structure) and records an
`Entry` in the registry. Every check happens here, at compile time:

- an id is issued once in the whole imported environment;
- every claim has a title and says what it does (`does`); a move also says what follows (`sees`);
- `in ^P` names a place that exists;
- a move has a handler per trigger, and each handler has `apply` (or `emit`), `post` and a
  `sound` proof, so a move without a proof does not compile;
- a flow's witness names moves that exist, and its `live` and `reaches` proofs check;
- a retired id says why;
- no move is declared after `moves%` collected its namespace, and no claim after `claims%`. -/

public meta section

namespace Cairn.Claims
open Lean Elab Command Term Meta

/-! ### Syntax

The command keywords are not reserved: `move`, `place` and the rest stay usable as identifiers
(`ClaimKind.place`, a field called `move`). A plain `&"move"` is not found by the command
parser when it starts a command, so each keyword is a non-reserved symbol that also indexes
under identifiers. -/

open Lean.Parser in
/-- A command keyword that is not reserved. -/
def claimKw (s : String) : Parser := nonReservedSymbol s (includeIdent := true)

open Lean.Parser in section
def moveKw : Parser := claimKw "move"
def flowKw : Parser := claimKw "flow"
def invariantKw : Parser := claimKw "invariant"
def assumeKw : Parser := claimKw "assume"
def placeKw : Parser := claimKw "place"
def retireKw : Parser := claimKw "retire"
end

/-- A claim id, `^N`. -/
syntax claimRef := "^" num
/-- One action of a flow's witness: `press ^1`, `press ^5#12`, `edit ^3 (.insert "a")`. -/
syntax claimStep := ident claimRef ("#" num)? (ppSpace colGt term:max)?
/-- A prose clause (`does "…"`) or a definition clause (`post s' := …`, `sound := by …`). -/
syntax claimItem := ident (str <|> ((ppSpace colGt binderIdent)* " := " term))
syntax claimWitness := &"witness" sepBy1(claimStep, ", ")
/-- A move's handler for one trigger: `on press`, `on edit (op : TextOp)`. -/
syntax claimOn := &"on" ident ("(" ident " : " term ")")? many1Indent(claimItem)
syntax claimClause := claimWitness <|> claimOn <|> claimItem
syntax claimBinder := "(" ident " : " term ")"
syntax claimIn := " in " claimRef

syntax (name := moveCmd) (docComment)? moveKw claimRef ident claimBinder (claimBinder)? str
  (claimIn)? " where" many1Indent(claimClause) : command
syntax (name := flowCmd) (docComment)? flowKw claimRef ident str " for " term
  (claimIn)? " where" many1Indent(claimClause) : command
syntax (name := invariantCmd) (docComment)? invariantKw claimRef ident str " for " term
  " where" many1Indent(claimClause) : command
syntax (name := assumeCmd) (docComment)? assumeKw claimRef ident str
  " where" many1Indent(claimClause) : command
syntax (name := placeCmd) (docComment)? placeKw claimRef ident str (claimIn)?
  " where" many1Indent(claimClause) : command
/-- A retired id: the claim is gone, its id stays issued. -/
syntax (name := retireCmd) retireKw claimRef ident str &"because" str : command

/-- The moves declared in a namespace (the current one by default), as a list. -/
syntax (name := movesTerm) "moves%" (ppSpace ident)? : term
/-- The `ClaimInfo` of every claim declared in a namespace (the current one by default),
including retired ids, ordered by id. -/
syntax (name := claimsTerm) "claims%" (ppSpace ident)? : term

/-! ### Reading clauses -/

inductive Item where
  | prose (name : Syntax) (val : String)
  | defn (name : Syntax) (binders : Array Syntax) (rhs : Term)
  | on (trigger : Syntax) (op : Option (Ident × Term)) (items : Array Item)
  | witness (ref : Syntax) (steps : Array Syntax)
deriving Inhabited

def Item.ref : Item → Syntax
  | .prose n _ | .defn n _ _ | .on n _ _ | .witness n _ => n

def Item.key : Item → String
  | .prose n _ | .defn n _ _ => n.getId.toString
  | .on t _ _ => s!"on {t.getId}"
  | .witness .. => "witness"

def parseItem (stx : Syntax) : CommandElabM Item := do
  let name := stx[0]
  let rhs := stx[1]
  if let some s := rhs.isStrLit? then
    return .prose name s
  else
    return .defn name rhs[0].getArgs ⟨rhs[2]⟩

def parseClause (stx : Syntax) : CommandElabM Item := do
  let c := stx[0]
  if c.isOfKind ``claimWitness then
    return .witness c c[1].getSepArgs
  else if c.isOfKind ``claimOn then
    let g := c[2]
    let op := if g.getNumArgs == 0 then none else some ((⟨g[1]⟩ : Ident), (⟨g[3]⟩ : Term))
    return .on c[1] op (← c[3].getArgs.mapM parseItem)
  else
    parseItem c

def refId (stx : Syntax) : ClaimId := stx[1].isNatLit?.getD 0

/-- The clauses of one claim, checked against the names its kind allows. -/
structure Clauses where
  items : Array Item

def Clauses.read (body : Syntax) (allowed : List String) (kind : String) :
    CommandElabM Clauses := do
  let items ← body.getArgs.mapM parseClause
  let mut seen : Std.HashSet String := {}
  for it in items do
    let k := it.key
    let base := match it with | .on .. => "on" | _ => k
    unless allowed.contains base do
      throwErrorAt it.ref m!"`{k}` is not a clause of a {kind}; expected one of {allowed}"
    if seen.contains k then
      throwErrorAt it.ref m!"`{k}` is given twice"
    seen := seen.insert k
  return ⟨items⟩

def Clauses.prose? (c : Clauses) (n : String) : Option String :=
  c.items.findSome? fun | .prose x v => if x.getId.toString == n then some v else none | _ => none

def Clauses.defn? (c : Clauses) (n : String) : Option (Syntax × Array Syntax × Term) :=
  c.items.findSome? fun
    | .defn x bs t => if x.getId.toString == n then some (x, bs, t) else none
    | _ => none

/-- A definition clause that must be present, with exactly `arity` binders. -/
def needDefn (items : Array Item) (ref : Syntax) (n what : String) (arity : Nat) :
    CommandElabM (Array Syntax × Term) := do
  match (Clauses.mk items).defn? n with
  | none => throwErrorAt ref m!"missing `{n}`: {what}"
  | some (x, bs, t) =>
    unless bs.size == arity do
      throwErrorAt x m!"`{n}` takes {arity} name(s) here, got {bs.size}"
    return (bs, t)

def optDefn (items : Array Item) (n : String) (arity : Nat) :
    CommandElabM (Option (Array Syntax × Term)) := do
  match (Clauses.mk items).defn? n with
  | none => return none
  | some (x, bs, t) =>
    unless bs.size == arity do
      throwErrorAt x m!"`{n}` takes {arity} name(s) here, got {bs.size}"
    return some (bs, t)

def needProse (c : Clauses) (ref : Syntax) (n what : String) : CommandElabM String := do
  match c.prose? n with
  | some v =>
    if v.trimAscii.isEmpty then throwErrorAt ref m!"`{n}` is empty: {what}"
    return v
  | none => throwErrorAt ref m!"missing `{n} \"…\"`: {what}"

/-! ### Checks shared by every claim -/

def checkTitle (ref : Syntax) (title : String) : CommandElabM Unit := do
  if title.trimAscii.isEmpty then throwErrorAt ref "a claim needs a title"
  if title.any (fun c => c == '\t' || c == '\n') then
    throwErrorAt ref "a title is one line, without tabs"

/-- An id is issued once in the whole imported environment. -/
def checkFresh (ref : Syntax) (id : ClaimId) : CommandElabM Unit := do
  let env ← getEnv
  for (a, b) in clashes env do
    throwErrorAt ref m!"claim id ^{a.info.id} is issued twice in the imported modules: \
      {a.label} and {b.label}"
  if id == 0 then throwErrorAt ref "claim ids start at ^1"
  if let some e := lookup? env id then
    throwErrorAt ref m!"claim id ^{id} is already issued: {e.label}. Ids are never reused; \
      take a new one"

def checkPlace (stx : Syntax) : CommandElabM (Option ClaimId) := do
  match stx.getOptional? with
  | none => return none
  | some g =>
    let p := refId g[1]
    match lookup? (← getEnv) p with
    | some e =>
      unless e.info.kind == .place do
        throwErrorAt g m!"^{p} is not a place: {e.label}"
      if e.info.retired.isSome then throwErrorAt g m!"place ^{p} is retired"
      return some p
    | none => throwErrorAt g m!"unknown place ^{p}: declare it with `place ^{p} …` first"

def checkUnsealed (ref : Syntax) (dispatched : Bool) : CommandElabM Unit := do
  let ns ← getCurrNamespace
  let (moves, all) := sealedExt.getState (← getEnv)
  if all.contains ns then
    throwErrorAt ref m!"`claims%` already collected namespace {ns}; declare claims before it"
  if dispatched && moves.contains ns then
    throwErrorAt ref m!"`moves%` already collected namespace {ns}; a move declared now would \
      never be dispatched. Declare moves before it"

def register (e : Entry) : CommandElabM Unit :=
  modifyEnv (registry.addEntry · e)

/-! ### Building declarations -/

def lit (n : Nat) : Term := Syntax.mkNumLit (toString n)
def strLit (s : String) : Term := Syntax.mkStrLit s

def cid (n : Name) : Ident := mkCIdent n

/-- An explicit binder from a name the user wrote: an identifier, or a `binderIdent` (which may
be `_`). -/
def binder (x : Syntax) (t : Term) : CommandElabM (TSyntax ``Lean.Parser.Term.bracketedBinder) := do
  let x := if x.isOfKind ``Lean.binderIdent then x[0] else x
  if x.isIdent then `(bracketedBinder| ($(⟨x⟩):ident : $t))
  else `(bracketedBinder| (_ : $t))

/-- `def name binders : type := body`, then its doc string. -/
def mkDef (name : Name) (bs : Array (Syntax × Term)) (type body : Term) (doc : String := "")
    (reducible := false) : CommandElabM Unit := do
  let binders ← bs.mapM fun (x, t) => binder x t
  let id := mkIdent name
  -- In a `module`, generated declarations are public with their bodies exposed, so the
  -- importing modules' proofs (and `decide`) can unfold them.
  let inModule := (← getEnv).header.isModule
  match reducible, inModule with
  | true, true => elabCommand (← `(@[reducible, expose] public def $id:ident $binders* : $type := $body))
  | true, false => elabCommand (← `(@[reducible] public def $id:ident $binders* : $type := $body))
  | false, true => elabCommand (← `(@[expose] public def $id:ident $binders* : $type := $body))
  | false, false => elabCommand (← `(public def $id:ident $binders* : $type := $body))
  unless doc.isEmpty do addDocStringCore ((← getCurrNamespace) ++ name) doc

def mkThm (name : Name) (type : Term) (proof : Term) (doc : String := "") :
    CommandElabM Unit := do
  elabCommand (← `(public theorem $(mkIdent name):ident : $type := $proof))
  unless doc.isEmpty do addDocStringCore ((← getCurrNamespace) ++ name) doc

def foralls (bs : Array (Ident × Term)) (body : Term) : CommandElabM Term :=
  bs.foldrM (fun (x, t) acc => `(∀ ($x : $t), $acc)) body

def app (f : Name) (args : Array Term) : Term := Syntax.mkApp (cid f) args

def mkInfo (name : Name) (id : ClaimId) (kind : Name) (title does sees : String)
    (place : Option ClaimId) (retired : Option String := none) : CommandElabM Unit := do
  let placeT ← match place with
    | some p => `(some $(lit p))
    | none => `(none)
  let retiredT ← match retired with
    | some r => `(some $(strLit r))
    | none => `(none)
  let kindT := cid (``Cairn.ClaimKind ++ kind)
  mkDef name #[] (← `(Cairn.ClaimInfo))
    (← `({ id := $(lit id), kind := $kindT, title := $(strLit title), does := $(strLit does),
           sees := $(strLit sees), place := $placeT, retired := $retiredT }))
    s!"The human half of claim ^{id}."
  -- A declaration named after the id: two modules that issue the same id cannot both be
  -- imported, even when neither imports the other.
  let issued := mkIdent (`_root_ ++ `Cairn.Claims.Issued ++ Name.mkSimple s!"^{id}")
  let target := cid ((← getCurrNamespace) ++ name)
  if (← getEnv).header.isModule then
    elabCommand (← `(@[reducible, expose] public def $issued:ident : Cairn.ClaimInfo := $target))
  else
    elabCommand (← `(@[reducible] public def $issued:ident : Cairn.ClaimInfo := $target))

def docOf (doc? : Option Syntax) (fallback : String) : CommandElabM String :=
  match doc? with
  | some d => getDocStringText ⟨d⟩
  | none => pure fallback

def triggers : List (String × Name) :=
  [("press", ``Cairn.Trigger.press), ("doublePress", ``Cairn.Trigger.doublePress),
   ("edit", ``Cairn.Trigger.edit), ("submit", ``Cairn.Trigger.submit),
   ("cancel", ``Cairn.Trigger.cancel), ("blur", ``Cairn.Trigger.blur)]

/-! ### `move` -/

@[command_elab moveCmd] def elabMove : CommandElab := fun stx => do
  let doc? := stx[0].getOptional?
  let id := refId stx[2]
  let nameStx := stx[3]
  let name := nameStx.getId
  let sB := stx[4]
  let kB? := stx[5].getOptional?
  let titleStx := stx[6]
  let title := titleStx.isStrLit?.getD ""
  checkTitle titleStx title
  checkFresh stx[2] id
  checkUnsealed stx[1] true
  let place ← checkPlace stx[7]
  let c ← Clauses.read stx[9] ["does", "sees", "enabled", "on"] "move"
  let does ← needProse c stx[1] "does" "what the person does"
  let sees ← needProse c stx[1] "sees" "what follows"
  let ns ← getCurrNamespace
  let full := ns ++ name
  let S : Term := ⟨sB[3]⟩
  let s : Ident := ⟨sB[1]⟩
  let kk : Option Ident := kB?.map (⟨·[1]⟩)
  if let some kb := kB? then
    unless kb[3].isIdent && kb[3].getId == `Nat do
      throwErrorAt kb[3] "a move's second binder is its control key, of type `Nat`"
  let natT ← `(Nat)
  -- the move's own binders: the state, and the key when controls are keyed
  let own : Array (Ident × Term) := #[(s, S)] ++ (kk.map (·, natT)).toArray
  let ownT : Array Term := own.map (·.1)
  -- enabled
  let enabled? ← optDefn c.items "enabled" 0
  if let some (_, rhs) := enabled? then
    mkDef (name ++ `enabled) (own.map fun (x, t) => (x.raw, t)) (← `(Bool)) (← `(($rhs : Bool)))
      s!"When ^{id} {title} is available."
  let σ := mkIdent `σ
  let κ := mkIdent `κ
  let ο := mkIdent `ο
  let σ' := mkIdent `σ'
  let η := mkIdent `η
  let wrapArgs : Array Term := #[σ] ++ (if kk.isSome then #[κ] else #[])
  let enabledFull : Term ← match enabled? with
    | some _ => `(fun $σ $κ => $(app (full ++ `enabled) wrapArgs))
    | none => `(fun _ _ => true)
  -- handlers
  let ons := c.items.filterMap fun | .on t op is => some (t, op, is) | _ => none
  if ons.isEmpty then
    throwErrorAt stx[1] "a move needs at least one handler: `on press`, `on edit (op : TextOp)`, …"
  let mut handlers : Array Term := #[]
  let mut statement : Array Name := (if enabled?.isSome then #[full ++ `enabled] else #[])
  let mut evidence : Array (String × Name) := #[]
  let mut trigNames : Array String := #[]
  -- for `name.preserves`: one obligation per handler, and how to use it
  let P := mkIdent `P
  let mut presArgs : Array (Ident × Term) := #[]
  let mut presProofs : Array Term := #[]
  for (tStx, op?, items) in ons do
    let tName := tStx.getId.toString
    let some (_, tCtor) := triggers.find? (·.1 == tName)
      | throwErrorAt tStx m!"unknown trigger `{tName}`; expected one of {triggers.map (·.1)}"
    let isEdit := tName == "edit"
    if isEdit && op?.isNone then
      throwErrorAt tStx "`on edit` names its text operation: `on edit (op : TextOp)`"
    if !isEdit && op?.isSome then
      throwErrorAt tStx m!"only `edit` carries a text operation; `{tName}` has none"
    for it in items do
      unless ["apply", "emit", "post", "sound"].contains it.key do
        throwErrorAt it.ref m!"`{it.key}` is not a handler clause; expected apply or emit, post, sound"
    let hns := name ++ Name.mkSimple tName
    let fh := full ++ Name.mkSimple tName
    let args : Array (Ident × Term) := own ++ (op?.map fun (o, t) => (o, t)).toArray
    let argsB := args.map fun (x, t) => (x.raw, t)
    let argT : Array Term := args.map (·.1)
    -- apply or emit
    let applyC := (Clauses.mk items).defn? "apply"
    let emitC := (Clauses.mk items).defn? "emit"
    let emits ← match applyC, emitC with
      | some _, some (x, _, _) => throwErrorAt x "give `apply` (new state) or `emit` (new state and effects), not both"
      | some (x, bs, rhs), none => do
        unless bs.isEmpty do throwErrorAt x "`apply` takes no names here: the move's binders are in scope"
        mkDef (hns ++ `apply) argsB S rhs s!"What ^{id} does on {tName}."
        pure false
      | none, some (x, bs, rhs) => do
        unless bs.isEmpty do throwErrorAt x "`emit` takes no names here: the move's binders are in scope"
        mkDef (hns ++ `emit) argsB (← `($S × List Cairn.Effect)) rhs
          s!"What ^{id} does on {tName}, with the effects it asks the host to run."
        pure true
      | none, none => throwErrorAt tStx "missing `apply := …` (or `emit := …`): what the move does"
    -- post
    let (pbs, prhs) ← needDefn items tStx "post" "what must follow, as `post s' := …`" 1
    mkDef (hns ++ `post) (argsB.push (pbs[0]!, S)) (← `(Prop)) prhs
      s!"What must follow ^{id} {title} on {tName}: {sees}"
    -- sound
    let (_, proof) ← needDefn items tStx "sound" "the proof that `apply` meets `post`" 0
    let result : Term :=
      if emits then app (fh ++ `emit) argT else app (fh ++ `apply) argT
    let result ← if emits then `(($result).1) else pure result
    let concl := Syntax.mkApp (cid (full ++ Name.mkSimple tName ++ `post)) (argT.push result)
    let body ← match enabled? with
      | some _ => `($(app (full ++ `enabled) ownT) = true → $concl)
      | none => pure concl
    mkThm (hns ++ `sound) (← foralls args body) proof
      s!"^{id} {title}, on {tName}: whenever the move is enabled, `apply` meets `post`."
    -- the handler, in the generic form dispatch uses
    let wrap : Array Term := wrapArgs ++ (if isEdit then #[ο] else #[])
    let applyFull : Term ← if emits then pure (app (fh ++ `emit) wrap)
      else `(($(app (fh ++ `apply) wrap), []))
    let postFull := app (fh ++ `post) (wrap.push σ')
    let soundFull := app (fh ++ `sound) (wrap ++ (if enabled?.isSome then #[η] else #[]))
    let h ← if isEdit then
        `(Cairn.Claims.Handler.edit (enabled := $enabledFull)
            (fun $σ $κ $ο => $applyFull) (fun $σ $κ $ο $σ' => $postFull)
            (fun $σ $κ $ο $η => $soundFull))
      else
        `(Cairn.Claims.Handler.simple (enabled := $enabledFull) $(cid tCtor)
            (fun $σ $κ => $applyFull) (fun $σ $κ $σ' => $postFull)
            (fun $σ $κ $η => $soundFull))
    handlers := handlers.push h
    let pBody ← `($P $result)
    let pBody ← `($P $(s) → $pBody)
    let pBody ← match enabled? with
      | some _ => `($(app (full ++ `enabled) ownT) = true → $pBody)
      | none => pure pBody
    let ob := mkIdent (Name.mkSimple tName)
    presArgs := presArgs.push (ob, ← foralls args pBody)
    let hs := mkIdent `hs
    let use := Syntax.mkApp ob (wrap ++ (if enabled?.isSome then #[η] else #[]) |>.push hs)
    let pp ← if isEdit then
        `(Cairn.Claims.Handler.edit_preserves (fun $σ $κ $ο $η $hs => $use))
      else
        `(Cairn.Claims.Handler.simple_preserves (fun $σ $κ $η $hs => $use))
    presProofs := presProofs.push pp
    statement := statement.push (fh ++ `post)
    evidence := evidence.push (s!"sound {tName}", fh ++ `sound)
    trigNames := trigNames.push tName
  mkInfo (name ++ `info) id `move title does sees place
  let doc ← docOf doc? s!"**^{id} {title}** (move)\n\nDoes: {does}\n\nSees: {sees}"
  mkDef name #[] (← `(Cairn.Claims.Move $S))
    (← `({ info := $(cid (full ++ `info)), enabled := $enabledFull, handlers := [$handlers,*] }))
    doc
  let presType ← presArgs.foldrM (init := ← `(Cairn.Claims.Move.Preserves $(cid full) $P))
    fun (x, t) acc => `(($x : $t) → $acc)
  let presProof ← presProofs.foldrM (init := ← `(Cairn.Claims.Handler.all_nil))
    fun p acc => `(Cairn.Claims.Handler.all_cons $p $acc)
  let presLam ← presArgs.foldrM (init := presProof) fun (x, _) acc => `(fun $x => $acc)
  mkThm (name ++ `preserves) (← `(∀ ($P : $S → Prop), $presType)) (← `(fun $P => $presLam))
    s!"To show every handler of ^{id} keeps a property, show it in the move's own terms."
  register {
    info := { id, kind := .move, title, does, sees, place }
    ns, decl := full, infoDecl := full ++ `info, module := ← getMainModule
    statement, evidence, triggers := trigNames, keyed := kk.isSome }

/-! ### `flow` -/

def stepAction (step : Syntax) : CommandElabM (Term × ClaimId) := do
  let t := step[0].getId.toString
  let id := refId step[1]
  let key := if step[2].getNumArgs == 0 then 0 else (step[2][1].isNatLit?).getD 0
  let arg? : Option Term :=
    if step[3].getNumArgs == 0 then none else some ⟨step[3][step[3].getNumArgs - 1]⟩
  let some (_, _) := triggers.find? (·.1 == t)
    | throwErrorAt step[0] m!"unknown trigger `{t}`; expected one of {triggers.map (·.1)}"
  match lookup? (← getEnv) id with
  | some e =>
    unless e.info.kind == .move && e.info.retired.isNone do
      throwErrorAt step[1] m!"a witness step names a move, and ^{id} is not one: {e.label}"
    unless e.triggers.contains t do
      throwErrorAt step[0] m!"move ^{id} has no `on {t}` handler"
  | none => throwErrorAt step[1] m!"unknown move ^{id}"
  let ctl ← `({ claim := $(lit id), key := $(lit key) : Cairn.ControlRef })
  let a ← match t, arg? with
    | "edit", some op => `(Cairn.Action.edit $ctl $op)
    | "edit", none => throwErrorAt step "an `edit` step needs its text operation: `edit ^3 (.insert \"a\")`"
    | _, some x => throwErrorAt x m!"`{t}` takes no argument"
    | _, none => `($(cid (``Cairn.Action ++ Name.mkSimple t)) $ctl)
  return (a, id)

@[command_elab flowCmd] def elabFlow : CommandElab := fun stx => do
  let doc? := stx[0].getOptional?
  let id := refId stx[2]
  let name := stx[3].getId
  let titleStx := stx[4]
  let title := titleStx.isStrLit?.getD ""
  let M : Term := ⟨stx[6]⟩
  checkTitle titleStx title
  checkFresh stx[2] id
  checkUnsealed stx[1] false
  let place ← checkPlace stx[7]
  let c ← Clauses.read stx[9] ["does", "sees", "goal", "witness", "reaches"] "flow"
  let does ← needProse c stx[1] "does" "the goal, in words"
  let sees := (c.prose? "sees").getD ""
  let full := (← getCurrNamespace) ++ name
  let SM ← `(Cairn.Claims.StateOf $M)
  let (gbs, grhs) ← needDefn c.items stx[1] "goal" "the goal, as `goal s := …`" 1
  mkDef (name ++ `goal) #[(gbs[0]!, SM)] (← `(Prop)) grhs s!"The goal of ^{id} {title}: {does}"
  let some (_, steps) := c.items.findSome? fun | .witness r ss => some (r, ss) | _ => none
    | throwErrorAt stx[1] "missing `witness …`: the actions that reach the goal from the start"
  let acts ← steps.mapM stepAction
  mkDef (name ++ `witness) #[] (← `(List Cairn.Action)) (← `([$(acts.map (·.1)),*]))
    s!"A path to the goal of ^{id}."
  let w := cid (full ++ `witness)
  mkThm (name ++ `live)
    (← `(Cairn.Claims.Machine.live $M (Cairn.Claims.Machine.init $M) $w = true))
    (← `(by decide)) s!"Every step of ^{id}'s witness is answered by an enabled move."
  let reachesProof ← match ← optDefn c.items "reaches" 0 with
    | some (_, p) => pure p
    | none => `(by unfold $(cid (full ++ `goal)); decide)
  mkThm (name ++ `reaches)
    (← `($(cid (full ++ `goal)) (Cairn.Claims.Machine.run $M (Cairn.Claims.Machine.init $M) $w)))
    reachesProof s!"The witness of ^{id} reaches its goal."
  mkInfo (name ++ `info) id `flow title does sees place
  let doc ← docOf doc? s!"**^{id} {title}** (flow)\n\n{does}"
  mkDef name #[] (← `(Cairn.Claims.Flow $M))
    (← `({ info := $(cid (full ++ `info)), goal := $(cid (full ++ `goal)), witness := $w,
           live := $(cid (full ++ `live)), reaches := $(cid (full ++ `reaches)) }))
    doc
  let machine ← liftTermElabM do
    let e ← elabTerm M none
    pure (e.getAppFn.constName?)
  register {
    info := { id, kind := .flow, title, does, sees, place }
    ns := ← getCurrNamespace, decl := full, infoDecl := full ++ `info, module := ← getMainModule
    statement := #[full ++ `goal, full ++ `witness]
    evidence := #[("live", full ++ `live), ("reaches", full ++ `reaches)]
    passes := acts.map (·.2), machine }

/-! ### `invariant` -/

/-- The definitions to unfold, from `holds` down its body's head, before `Decidable` of the
property can be synthesized; `none` when it can't be, even after unfolding a few. -/
def decidableUnfolds (holds : Name) (SM : Term) : CommandElabM (Option (Array Name)) :=
  liftTermElabM do
    let ty ← elabType SM
    withLocalDeclD `s ty fun s => do
      let mut t := mkApp (← mkConstWithLevelParams holds) s
      let mut names : Array Name := #[]
      for _ in [0:8] do
        let found ← try pure (← synthInstance? (mkApp (mkConst ``Decidable) t)).isSome
          catch _ => pure false
        if found then return some names
        let some c := t.getAppFn.constName? | return none
        let some t' ← unfoldDefinition? t | return none
        names := names.push c
        t := t'.headBeta
      return none

@[command_elab invariantCmd] def elabInvariant : CommandElab := fun stx => do
  let doc? := stx[0].getOptional?
  let id := refId stx[2]
  let name := stx[3].getId
  let titleStx := stx[4]
  let title := titleStx.isStrLit?.getD ""
  let M : Term := ⟨stx[6]⟩
  checkTitle titleStx title
  checkFresh stx[2] id
  checkUnsealed stx[1] false
  let c ← Clauses.read stx[8] ["does", "holds", "init", "step", "receive"] "invariant"
  let does ← needProse c stx[1] "does" "the property, in words"
  let full := (← getCurrNamespace) ++ name
  let SM ← `(Cairn.Claims.StateOf $M)
  let (hbs, hrhs) ← needDefn c.items stx[1] "holds" "the property, as `holds s := …`" 1
  mkDef (name ++ `holds) #[(hbs[0]!, SM)] (← `(Prop)) hrhs s!"^{id} {title}: {does}"
  let holds := cid (full ++ `holds)
  -- Runnable invariants (docs/fuzz.md): `check` is `decide`, so it agrees with `holds` by
  -- construction. Generated only when `Decidable` can be found.
  if let some names ← decidableUnfolds (full ++ `holds) SM then
    let sId := mkIdent `s
    let inst ← if names.isEmpty then `(inferInstance)
      else `(by unfold $(names.map cid)*; infer_instance)
    mkDef (name ++ `check) #[(sId, SM)] (← `(Bool)) (← `(@decide ($holds $sId) $inst))
      s!"^{id} {title}, decided: what `lake exe fuzz` runs after every step."
  let (_, initP) ← needDefn c.items stx[1] "init" "the proof that it holds initially" 0
  mkThm (name ++ `init) (← `($holds (Cairn.Claims.Machine.init $M))) initP
    s!"^{id} holds in the initial state."
  let (_, stepP) ← needDefn c.items stx[1] "step" "the proof that every update preserves it" 0
  mkThm (name ++ `step)
    (← `(∀ (s : $SM) (a : Cairn.Action), $holds s →
          $holds (Cairn.Claims.Machine.update $M s a).1)) stepP
    s!"Every update, so every move, preserves ^{id}."
  -- Messages from the world (`Machine.receive`): a proof is needed only when the machine
  -- hears the world; for one that doesn't, `receive` leaves the state alone.
  let recvP ← match ← optDefn c.items "receive" 0 with
    | some (_, p) => pure p
    | none => `(fun _ _ h => h)
  mkThm (name ++ `receive)
    (← `(∀ (s : $SM) (m : Cairn.Msg), $holds s →
          $holds (Cairn.Claims.Machine.receive $M s m).1)) recvP
    s!"Every message from the world preserves ^{id}."
  mkInfo (name ++ `info) id `invariant title does "" none
  let doc ← docOf doc? s!"**^{id} {title}** (invariant)\n\n{does}"
  mkDef name #[] (← `(Cairn.Claims.Invariant $M))
    (← `({ info := $(cid (full ++ `info)), holds := $holds, init := $(cid (full ++ `init)),
           step := $(cid (full ++ `step)), recv := $(cid (full ++ `receive)) }))
    doc
  mkThm (name ++ `reachable)
    (← `(∀ (s : $SM), Cairn.Claims.Machine.Reachable $M s → $holds s))
    (← `(fun _ h => Cairn.Claims.Invariant.reachable $(cid full) h))
    s!"^{id} holds in every reachable state."
  mkThm (name ++ `reachableAll)
    (← `(∀ (s : $SM), Cairn.Claims.Machine.ReachableAll $M s → $holds s))
    (← `(fun _ h => Cairn.Claims.Invariant.reachableAll $(cid full) h))
    s!"^{id} holds in every state reachable by actions and messages from the world."
  let machine ← liftTermElabM do
    let e ← elabTerm M none
    pure (e.getAppFn.constName?)
  register {
    info := { id, kind := .invariant, title, does }
    ns := ← getCurrNamespace, decl := full, infoDecl := full ++ `info, module := ← getMainModule
    statement := #[full ++ `holds]
    evidence := #[("init", full ++ `init), ("step", full ++ `step),
      ("receive", full ++ `receive), ("reachable", full ++ `reachable),
      ("reachableAll", full ++ `reachableAll)]
    machine }

/-! ### `assume` and `place` -/

@[command_elab assumeCmd] def elabAssume : CommandElab := fun stx => do
  let doc? := stx[0].getOptional?
  let id := refId stx[2]
  let name := stx[3].getId
  let titleStx := stx[4]
  let title := titleStx.isStrLit?.getD ""
  checkTitle titleStx title
  checkFresh stx[2] id
  checkUnsealed stx[1] false
  let c ← Clauses.read stx[6] ["does", "statement", "check"] "assumption"
  let does ← needProse c stx[1] "does" "what is assumed, in words"
  let check? := c.prose? "check"
  if let some k := check? then
    unless !k.isEmpty && k.all fun ch => ch.isLower || ch.isDigit || ch == '.' || ch == '-' do
      throwErrorAt stx[1] m!"`check` names a fuzzer check, like \"frame.decode\" (lowercase, digits, `.` and `-`); got {repr k}"
  let full := (← getCurrNamespace) ++ name
  let stmt? ← optDefn c.items "statement" 0
  let stmt ← match stmt? with
    | some (_, t) => pure t
    | none => `(True)
  mkDef (name ++ `statement) #[] (← `(Prop)) stmt
    s!"Assumed, never proved (^{id} {title}): {does}"
  mkInfo (name ++ `info) id `assume title does "" none
  let doc ← docOf doc? s!"**^{id} {title}** (assumption)\n\n{does}"
  mkDef name #[] (← `(Cairn.Claims.Assumption))
    (← `({ info := $(cid (full ++ `info)), statement := $(cid (full ++ `statement)) })) doc
  register {
    info := { id, kind := .assume, title, does }
    ns := ← getCurrNamespace, decl := full, infoDecl := full ++ `info, module := ← getMainModule
    statement := if stmt?.isSome then #[full ++ `statement] else #[]
    check := check? }

@[command_elab placeCmd] def elabPlace : CommandElab := fun stx => do
  let doc? := stx[0].getOptional?
  let id := refId stx[2]
  let name := stx[3].getId
  let titleStx := stx[4]
  let title := titleStx.isStrLit?.getD ""
  checkTitle titleStx title
  checkFresh stx[2] id
  checkUnsealed stx[1] false
  let place ← checkPlace stx[5]
  let c ← Clauses.read stx[7] ["does"] "place"
  let does ← needProse c stx[1] "does" "what this region of the view is for"
  let full := (← getCurrNamespace) ++ name
  mkInfo (name ++ `info) id `place title does "" place
  let doc ← docOf doc? s!"**^{id} {title}** (place)\n\n{does}"
  mkDef name #[] (← `(Cairn.Claims.Place)) (← `({ info := $(cid (full ++ `info)) })) doc
  register {
    info := { id, kind := .place, title, does, place }
    ns := ← getCurrNamespace, decl := full, infoDecl := full ++ `info, module := ← getMainModule }

/-! ### `retire` -/

@[command_elab retireCmd] def elabRetire : CommandElab := fun stx => do
  let id := refId stx[1]
  let kindStx := stx[2]
  let some kind := ClaimKind.ofName? kindStx.getId.toString
    | throwErrorAt kindStx "expected a claim kind: move, flow, invariant, assume or place"
  let title := stx[3].isStrLit?.getD ""
  let reason := stx[5].isStrLit?.getD ""
  checkTitle stx[3] title
  if reason.trimAscii.isEmpty then
    throwErrorAt stx[5] "a retired claim says why it was retired"
  checkFresh stx[1] id
  checkUnsealed stx[0] false
  let name := Name.mkSimple s!"retired_{id}"
  let full := (← getCurrNamespace) ++ name
  mkInfo name id (Name.mkSimple kind.name) title "" "" none (retired := some reason)
  register {
    info := { id, kind, title, retired := some reason }
    ns := ← getCurrNamespace, decl := full, infoDecl := full, module := ← getMainModule }

/-! ### Collecting claims -/

def nsOf (stx : Syntax) : TermElabM Name := do
  match stx.getOptional? with
  | some i => pure i.getId
  | none => getCurrNamespace

@[term_elab movesTerm] def elabMoves : TermElab := fun stx expected? => do
  let ns ← nsOf stx[1]
  let ms := (entries (← getEnv)).filter fun e =>
    e.ns == ns && e.info.kind == .move && e.info.retired.isNone
  modifyEnv (sealedExt.modifyState · fun (m, a) => (m.insert ns, a))
  let ids : Array Term := ms.map (cid ·.decl)
  elabTerm (← `([$ids,*])) expected?

@[term_elab claimsTerm] def elabClaims : TermElab := fun stx expected? => do
  let ns ← nsOf stx[1]
  let cs := (allEntries (← getEnv)).filter (·.ns == ns)
  modifyEnv (sealedExt.modifyState · fun (m, a) => (m, a.insert ns))
  let ids : Array Term := cs.map (cid ·.infoDecl)
  elabTerm (← `(([$ids,*] : List Cairn.ClaimInfo))) expected?

end Cairn.Claims
