/-! Which version may retire a claim (docs/claims.md, "Retiring needs a major version").

A released claim is a promise to every app that relies on it, so ending it is a breaking change:
a claim that a published version had active can be retired, or moved to another package, only in
a new major version, or in a new minor version while the package is at 0.x, following semver's
rule for 0.x as Cargo applies it. The nextpm registry checks the same rule when a version is
published (its cairn kind, `ledger.check`). The ledger (`lake exe ledger check`) reads the
package's last released tag and its `claims.lock`; this module is the pure part. -/

namespace Cairn.Claims.Release

/-- A semver version: `major.minor.patch`, and a pre-release such as `rc.1` or none (`""`). -/
structure Version where
  major : Nat
  minor : Nat
  patch : Nat
  pre : String := ""
deriving BEq, Repr, Inhabited

/-- `1.2.3` or `1.2.3-rc.1`. No build metadata, as `cairn.toml` and the registry allow none. -/
def Version.parse? (s : String) : Option Version :=
  match s.splitOn "-" with
  | [] => none
  | core :: pre =>
    match core.splitOn "." with
    | [a, b, c] => do
      let major ← a.toNat?
      let minor ← b.toNat?
      let patch ← c.toNat?
      let pre := "-".intercalate pre
      if pre.isEmpty && s.endsWith "-" then none else
      some { major, minor, patch, pre }
    | _ => none

def Version.render (v : Version) : String :=
  s!"{v.major}.{v.minor}.{v.patch}" ++ (if v.pre.isEmpty then "" else s!"-{v.pre}")

instance : ToString Version := ⟨Version.render⟩

/-- `a` comes before `b`, ignoring pre-releases: the order of releases. -/
def Version.lt (a b : Version) : Bool :=
  a.major < b.major || (a.major == b.major && (a.minor < b.minor ||
    (a.minor == b.minor && a.patch < b.patch)))

/-- Going from `old` to `new` is a breaking change: a new major version, or a new minor version
while at 0.x. -/
def breaking (old new : Version) : Bool :=
  if new.major != old.major then old.major < new.major
  else old.major == 0 && old.minor < new.minor

/-- The first version after `old` that may retire its claims. -/
def needed (old : Version) : Version :=
  if old.major == 0 then { major := 0, minor := old.minor + 1, patch := 0 }
  else { major := old.major + 1, minor := 0, patch := 0 }

/-- The release to check retirements against: the highest final version among `tags` (`v0.1.0`,
`v0.1.1`, …) that isn't after `current`. Release candidates aren't releases (docs/cli.md,
"Versions and tags"). -/
def latest (tags : List String) (current : Version) : Option Version :=
  tags.foldl (init := none) fun best tag =>
    match (if tag.startsWith "v" then Version.parse? (tag.drop 1).toString else none) with
    | some v =>
      if !v.pre.isEmpty || current.lt v then best
      else match best with
        | some b => if b.lt v then some v else best
        | none => some v
    | none => best

/-- The ids that `current` may not retire: active in the release `released` (`wasActive`) and
retired or moved now (`ended`), when `current` isn't a breaking version after it. -/
def blocked (released current : Version) (wasActive ended : List Nat) : List Nat :=
  if breaking released current then [] else wasActive.filter ended.contains

/-- The `version` of `[package]` in a `cairn.toml`. -/
def manifestVersion? (toml : String) : Option String := Id.run do
  let mut table := ""
  for raw in toml.splitOn "\n" do
    let line := raw.trimAscii.toString
    if line.startsWith "[" then
      table := line
      continue
    if table != "[package]" then continue
    match line.splitOn "=" with
    | [key, value] =>
      if key.trimAscii.toString == "version" then
        let v := (value.splitOn "#").headD "" |>.trimAscii.toString
        if v.length ≥ 2 && v.startsWith "\"" && v.endsWith "\"" then
          return some ((v.drop 1).toString.dropEnd 1).toString
    | _ => pure ()
  return none

end Cairn.Claims.Release
