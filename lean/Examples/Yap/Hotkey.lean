module

/-! # Yap: the dictation key

Mirrors `Hotkey.swift`: `config.json`'s `key` names the key to hold or tap. A bare modifier
(`rightCommand`, …, `fn`), `f1` to `f20`, or any key by its code (`keycode:105`). Names ignore
case, spaces, dashes and underscores, and the usual short forms work. Lean decides which key
it is and what the menu calls it; the host listens for the code and flag `Cmd.listen` names.

Differs from Swift in one place: case folding is ASCII only (Swift's `lowercased()` folds all
of Unicode; no key name has a letter outside ASCII). -/

@[expose] public section

namespace Examples.Yap

structure Hotkey where
  /-- The virtual key code macOS reports for it. -/
  code : Nat
  /-- For a modifier, the `NSEvent.ModifierFlags` raw value that tells press from release. -/
  modifier : Option Nat := none
  /-- For the menu and status text: "Right Command", "F13". -/
  name : String
deriving Repr, DecidableEq, Inhabited

namespace Hotkey

def shiftFlag : Nat := 131072      -- 1 << 17
def controlFlag : Nat := 262144    -- 1 << 18
def optionFlag : Nat := 524288     -- 1 << 19
def commandFlag : Nat := 1048576   -- 1 << 20
def functionFlag : Nat := 8388608  -- 1 << 23

def rightCommand : Hotkey := ⟨54, some commandFlag, "Right Command"⟩

def modifiers : List Hotkey := [
  ⟨54, some commandFlag, "Right Command"⟩, ⟨55, some commandFlag, "Left Command"⟩,
  ⟨61, some optionFlag, "Right Option"⟩, ⟨58, some optionFlag, "Left Option"⟩,
  ⟨62, some controlFlag, "Right Control"⟩, ⟨59, some controlFlag, "Left Control"⟩,
  ⟨60, some shiftFlag, "Right Shift"⟩, ⟨56, some shiftFlag, "Left Shift"⟩,
  ⟨63, some functionFlag, "fn"⟩]

/-- What people tend to write instead. -/
def aliases : List (String × String) := [
  ("rightcmd", "rightcommand"), ("rcmd", "rightcommand"),
  ("leftcmd", "leftcommand"), ("lcmd", "leftcommand"),
  ("rightalt", "rightoption"), ("ralt", "rightoption"), ("ropt", "rightoption"),
  ("leftalt", "leftoption"), ("lalt", "leftoption"), ("lopt", "leftoption"),
  ("rightctrl", "rightcontrol"), ("rctrl", "rightcontrol"),
  ("leftctrl", "leftcontrol"), ("lctrl", "leftcontrol"),
  ("rshift", "rightshift"), ("lshift", "leftshift"),
  ("function", "fn"), ("globe", "fn")]

/-- F1 to F20. Their codes follow no pattern. -/
def functionKeys : List Nat :=
  [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

/-- Lowercase, without spaces, dashes and underscores. -/
def normalize (s : String) : String :=
  String.ofList (s.toList.filterMap fun c =>
    if c == ' ' || c == '-' || c == '_' then none else some c.toLower)

def modifierNamed (n : String) : Option Hotkey :=
  modifiers.find? (normalize ·.name == n)

/-- Swift's `Int(_:)`/`UInt16(_:)` on what is left: an optional `+`, then decimal digits. -/
def parseNat? (cs : List Char) : Option Nat :=
  let ds := match cs with
    | '+' :: rest => rest
    | _ => cs
  if !ds.isEmpty && ds.all Char.isDigit then
    some (ds.foldl (fun n c => n * 10 + (c.toNat - '0'.toNat)) 0)
  else none

/-- `Hotkey(_:)`: the key a name means, or none for a name Yap doesn't know. -/
def parse (text : String) : Option Hotkey :=
  let key := normalize text
  match modifierNamed key <|> ((aliases.lookup key).bind modifierNamed) with
  | some k => some k
  | none =>
    match key.toList with
    | 'f' :: rest =>
      match parseNat? rest with
      | some n => if 1 ≤ n ∧ n ≤ 20 then some ⟨functionKeys.getD (n - 1) 0, none, s!"F{n}"⟩ else none
      | none => none
    | 'k' :: 'e' :: 'y' :: 'c' :: 'o' :: 'd' :: 'e' :: ':' :: rest =>
      match parseNat? rest with
      | some n =>
        if n ≤ 65535 then
          some ((modifiers.find? (·.code == n)).getD ⟨n, none, s!"Key {n}"⟩)
        else none
      | none => none
    | _ => none

end Hotkey
end Examples.Yap
