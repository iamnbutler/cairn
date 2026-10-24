module

/-! # Yap on Cairn: JSON and dates

What the app reads and writes, in the formats the original Yap uses, so the two share
`~/Library/Application Support/yap/` (docs/yap.md):

* **JSON**: a total parser (fuel is the input's length, so it is structural) and the two
  encodings Yap's `JSONEncoder`s produce: compact with sorted keys for a transcript line, pretty
  with sorted keys (`" : "`, two-space indent) for `config.json`. Only what Yap needs: objects,
  arrays, strings, integers (a number with a fraction or exponent is kept as text), booleans
  and null.
* **Dates**: the proleptic Gregorian calendar on day numbers (days since 1970-01-01), after
  Howard Hinnant's `days_from_civil` and `civil_from_days`, in integers. ISO 8601 in UTC
  (`2026-10-23T10:00:00Z`) is what `JSONEncoder.dateEncodingStrategy = .iso8601` writes; day
  files are named by the local date.

Nothing here is a claim's subject except through the app's functions that use it. -/

@[expose] public section

namespace Examples.Yap.Json

inductive Json where
  | null
  | bool (b : Bool)
  /-- An integer. -/
  | int (n : Int)
  /-- A number with a fraction or an exponent, as written. -/
  | num (text : String)
  | str (s : String)
  | arr (xs : List Json)
  | obj (kvs : List (String × Json))
deriving Repr, Inhabited

/-! ## Reading -/

def skipWs : List Char → List Char
  | c :: cs => if c = ' ' ∨ c = '\n' ∨ c = '\r' ∨ c = '\t' then skipWs cs else c :: cs
  | [] => []

def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c ∧ c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

def hex4 : List Char → Option (Nat × List Char)
  | a :: b :: c :: d :: rest => do
    let a ← hexVal a; let b ← hexVal b; let c ← hexVal c; let d ← hexVal d
    some (((a * 16 + b) * 16 + c) * 16 + d, rest)
  | _ => none

/-- The rest of a string literal after its opening quote: its characters (escapes decoded,
surrogate pairs joined) and what follows the closing quote. -/
def strBody : Nat → List Char → List Char → Option (String × List Char)
  | 0, _, _ => none
  | _ + 1, acc, '"' :: rest => some (String.ofList acc.reverse, rest)
  | fuel + 1, acc, '\\' :: e :: rest =>
    match e with
    | '"' => strBody fuel ('"' :: acc) rest
    | '\\' => strBody fuel ('\\' :: acc) rest
    | '/' => strBody fuel ('/' :: acc) rest
    | 'b' => strBody fuel ('\x08' :: acc) rest
    | 'f' => strBody fuel ('\x0c' :: acc) rest
    | 'n' => strBody fuel ('\n' :: acc) rest
    | 'r' => strBody fuel ('\r' :: acc) rest
    | 't' => strBody fuel ('\t' :: acc) rest
    | 'u' =>
      match hex4 rest with
      | some (hi, rest') =>
        if 0xD800 ≤ hi ∧ hi < 0xDC00 then
          match rest' with
          | '\\' :: 'u' :: more =>
            match hex4 more with
            | some (lo, rest'') =>
              if 0xDC00 ≤ lo ∧ lo < 0xE000 then
                strBody fuel (Char.ofNat (0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)) :: acc) rest''
              else none
            | none => none
          | _ => none
        else if 0xDC00 ≤ hi ∧ hi < 0xE000 then none
        else strBody fuel (Char.ofNat hi :: acc) rest'
      | none => none
    | _ => none
  | fuel + 1, acc, c :: rest => if c.toNat < 0x20 then none else strBody fuel (c :: acc) rest
  | _ + 1, _, [] => none

def isDigit (c : Char) : Bool := '0' ≤ c ∧ c ≤ '9'

/-- A number: `-`? digits, then optionally a fraction and an exponent. -/
def number (cs : List Char) : Option (Json × List Char) :=
  let (neg, cs) := match cs with
    | '-' :: r => (true, r)
    | r => (false, r)
  let ds := cs.takeWhile isDigit
  if ds.isEmpty then none
  else
    let rest := cs.dropWhile isDigit
    let n : Nat := ds.foldl (fun n c => n * 10 + (c.toNat - '0'.toNat)) 0
    let frac := match rest with
      | '.' :: r => let f := r.takeWhile isDigit; if f.isEmpty then none else some ('.' :: f, r.dropWhile isDigit)
      | r => some ([], r)
    match frac with
    | none => none
    | some (f, rest) =>
      let ex := match rest with
        | e :: r =>
          if e = 'e' ∨ e = 'E' then
            let (sg, r) := match r with
              | '+' :: r' => (['+'], r')
              | '-' :: r' => (['-'], r')
              | r' => ([], r')
            let d := r.takeWhile isDigit
            if d.isEmpty then none else some (e :: sg ++ d, r.dropWhile isDigit)
          else some ([], rest)
        | [] => some ([], rest)
      match ex with
      | none => none
      | some (x, rest) =>
        if f.isEmpty ∧ x.isEmpty then some (.int (if neg then -(n : Int) else n), rest)
        else some (.num (String.ofList ((if neg then ['-'] else []) ++ ds ++ f ++ x)), rest)

mutual
/-- A value, then what follows it. `fuel` bounds the nesting; the input's length is enough. -/
def value : Nat → List Char → Option (Json × List Char)
  | 0, _ => none
  | fuel + 1, cs =>
    match skipWs cs with
    | '{' :: rest => members fuel [] (skipWs rest) true
    | '[' :: rest => elements fuel [] (skipWs rest) true
    | '"' :: rest => (strBody (rest.length + 1) [] rest).map fun (s, r) => (.str s, r)
    | 't' :: 'r' :: 'u' :: 'e' :: rest => some (.bool true, rest)
    | 'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest => some (.bool false, rest)
    | 'n' :: 'u' :: 'l' :: 'l' :: rest => some (.null, rest)
    | cs' => number cs'

/-- An object's members after `{`, newest first in `acc`. -/
def members : Nat → List (String × Json) → List Char → Bool → Option (Json × List Char)
  | 0, _, _, _ => none
  | fuel + 1, acc, cs, first =>
    match cs with
    | '}' :: rest => if first then some (.obj [], rest) else none
    | '"' :: rest =>
      match strBody (rest.length + 1) [] rest with
      | none => none
      | some (k, rest) =>
        match skipWs rest with
        | ':' :: rest =>
          match value fuel rest with
          | none => none
          | some (v, rest) =>
            match skipWs rest with
            | ',' :: rest => members fuel ((k, v) :: acc) (skipWs rest) false
            | '}' :: rest => some (.obj ((k, v) :: acc).reverse, rest)
            | _ => none
        | _ => none
    | _ => none

/-- An array's elements after `[`. -/
def elements : Nat → List Json → List Char → Bool → Option (Json × List Char)
  | 0, _, _, _ => none
  | fuel + 1, acc, cs, first =>
    match cs with
    | ']' :: rest => if first then some (.arr [], rest) else none
    | cs =>
      match value fuel cs with
      | none => none
      | some (v, rest) =>
        match skipWs rest with
        | ',' :: rest => elements fuel (v :: acc) (skipWs rest) false
        | ']' :: rest => some (.arr (v :: acc).reverse, rest)
        | _ => none
end

/-- A whole document: one value and nothing after it but white space. -/
def parse (s : String) : Option Json :=
  let cs := s.toList
  match value (cs.length + 1) cs with
  | some (v, rest) => if skipWs rest = [] then some v else none
  | none => none

def Json.field (j : Json) (k : String) : Option Json :=
  match j with
  | .obj kvs => (kvs.find? (·.1 == k)).map (·.2)
  | _ => none

def Json.getStr : Json → Option String
  | .str s => some s
  | _ => none

def Json.getBool : Json → Option Bool
  | .bool b => some b
  | _ => none

def Json.getInt : Json → Option Int
  | .int n => some n
  | _ => none

/-! ## Writing -/

def hexDigit (n : Nat) : Char := if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

/-- A string literal as `JSONEncoder` writes it with `.withoutEscapingSlashes`: `"` and `\`
escaped, the control characters as `\n`, `\t`, … or `\u00xx`, everything else as it is. -/
def quote (s : String) : String :=
  let body := s.toList.flatMap fun c =>
    if c = '"' then ['\\', '"']
    else if c = '\\' then ['\\', '\\']
    else if c = '\n' then ['\\', 'n']
    else if c = '\r' then ['\\', 'r']
    else if c = '\t' then ['\\', 't']
    else if c = '\x08' then ['\\', 'b']
    else if c = '\x0c' then ['\\', 'f']
    else if c.toNat < 0x20 then ['\\', 'u', '0', '0', hexDigit (c.toNat / 16), hexDigit (c.toNat % 16)]
    else [c]
  "\"" ++ String.ofList body ++ "\""

def scalar : Json → String
  | .null => "null"
  | .bool b => if b then "true" else "false"
  | .int n => toString n
  | .num t => t
  | .str s => quote s
  | .arr _ | .obj _ => "null"

/-- A flat object, compact, keys as given (callers give them sorted). -/
def compact (kvs : List (String × Json)) : String :=
  "{" ++ ",".intercalate (kvs.map fun (k, v) => quote k ++ ":" ++ scalar v) ++ "}"

/-- A flat object as `JSONEncoder` writes it with `.prettyPrinted`: two-space indent and
`" : "`, keys as given. -/
def pretty (kvs : List (String × Json)) : String :=
  if kvs.isEmpty then "{\n\n}"
  else "{\n" ++ ",\n".intercalate (kvs.map fun (k, v) => "  " ++ quote k ++ " : " ++ scalar v) ++ "\n}"

#guard (parse "{\"text\":\"Hello, world.\",\"usage\":{\"type\":\"tokens\",\"total_tokens\":12.5e1}}" |>.bind (·.field "text") |>.bind Json.getStr) == some "Hello, world."
#guard (parse "{ \"a\" : [1, -2, {\"b\": null}], \"c\": \"\\u00e9\\ud83d\\ude00\\n\" }" |>.bind (·.field "c") |>.bind Json.getStr) == some "é😀\n"
#guard (parse "{\"a\":1,}").isNone && (parse "[1 2]").isNone && (parse "{\"a\":1} x").isNone
#guard (parse "\"\\ud800\"").isNone
#guard compact [("app", .str "Notes"), ("date", .str "2026-10-23T10:00:00Z"), ("text", .str "a \"b\"/c"), ("typed", .bool false)]
  == "{\"app\":\"Notes\",\"date\":\"2026-10-23T10:00:00Z\",\"text\":\"a \\\"b\\\"/c\",\"typed\":false}"
#guard pretty [("keepTranscripts", .bool true), ("retentionDays", .int 30)]
  == "{\n  \"keepTranscripts\" : true,\n  \"retentionDays\" : 30\n}"
#guard (parse (quote "tab\there \x01 é")).bind Json.getStr == some "tab\there \x01 é"

end Json

/-! ## Dates -/

namespace Dates

/-- Days since 1970-01-01 of a proleptic Gregorian date (`days_from_civil`). -/
def daysFromCivil (y m d : Int) : Int :=
  let y := if m ≤ 2 then y - 1 else y
  let era := (if 0 ≤ y then y else y - 399) / 400
  let yoe := y - era * 400
  let mp := (m + 9) % 12
  let doy := (153 * mp + 2) / 5 + d - 1
  let doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468

/-- The date of a day number (`civil_from_days`): year, month 1–12, day 1–31. -/
def civilFromDays (z : Int) : Int × Int × Int :=
  let z := z + 719468
  let era := (if 0 ≤ z then z else z - 146096) / 146097
  let doe := z - era * 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y := yoe + era * 400
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  (if m ≤ 2 then y + 1 else y, m, d)

def pad (w : Nat) (n : Int) : String :=
  let s := toString n.natAbs
  (if n < 0 then "-" else "") ++ String.ofList (List.replicate (w - s.length) '0') ++ s

/-- The local day number of a wall time (ms since the epoch, UTC) in a zone (seconds east of
UTC). -/
def localDay (wall zone : Int) : Int := (wall / 1000 + zone) / 86400

/-- `YYYY-MM-DD` of a day number. -/
def dayName (day : Int) : String :=
  let (y, m, d) := civilFromDays day
  s!"{pad 4 y}-{pad 2 m}-{pad 2 d}"

/-- ISO 8601 in UTC to the second, as `JSONEncoder`'s `.iso8601` writes it. -/
def iso (wall : Int) : String :=
  let secs := wall / 1000
  let sod := secs % 86400
  s!"{dayName (secs / 86400)}T{pad 2 (sod / 3600)}:{pad 2 (sod / 60 % 60)}:{pad 2 (sod % 60)}Z"

def digits (cs : List Char) : Option Int :=
  if !cs.isEmpty ∧ cs.all Json.isDigit then
    some (cs.foldl (fun n c => n * 10 + ((c.toNat : Int) - 48)) 0)
  else none

/-- The day number a file name `YYYY-MM-DD.jsonl` stands for, if it is one. -/
def parseDayFile (name : String) : Option Nat :=
  match name.toList with
  | [y1, y2, y3, y4, '-', m1, m2, '-', d1, d2, '.', 'j', 's', 'o', 'n', 'l'] => do
    let y ← digits [y1, y2, y3, y4]
    let m ← digits [m1, m2]
    let d ← digits [d1, d2]
    if 1 ≤ m ∧ m ≤ 12 ∧ 1 ≤ d ∧ d ≤ 31 then
      let n := daysFromCivil y m d
      if 0 ≤ n ∧ dayName n = s!"{pad 4 y}-{pad 2 m}-{pad 2 d}" then some n.toNat else none
    else none
  | _ => none

/-- The day file's name. -/
def dayFile (day : Int) : String := dayName day ++ ".jsonl"

/-- Wall milliseconds of an ISO 8601 date-time: `YYYY-MM-DDTHH:MM:SS`, an optional fraction,
then `Z` or `±HH:MM`. -/
def parseIso (s : String) : Option Int :=
  match s.toList with
  | y1 :: y2 :: y3 :: y4 :: '-' :: m1 :: m2 :: '-' :: d1 :: d2 :: 'T' :: h1 :: h2 :: ':' :: n1 :: n2 :: ':' :: s1 :: s2 :: rest => do
    let y ← digits [y1, y2, y3, y4]
    let mo ← digits [m1, m2]
    let d ← digits [d1, d2]
    let h ← digits [h1, h2]
    let mi ← digits [n1, n2]
    let se ← digits [s1, s2]
    let (ms, rest) := match rest with
      | '.' :: r =>
        let f := r.takeWhile Json.isDigit
        let f3 := (f ++ ['0', '0', '0']).take 3
        ((digits f3).getD 0, r.dropWhile Json.isDigit)
      | r => (0, r)
    let off ← match rest with
      | ['Z'] => some 0
      | [sg, a1, a2, ':', b1, b2] => do
        let a ← digits [a1, a2]
        let b ← digits [b1, b2]
        if sg = '+' then some (a * 3600 + b * 60) else if sg = '-' then some (-(a * 3600 + b * 60)) else none
      | _ => none
    if 1 ≤ mo ∧ mo ≤ 12 ∧ 1 ≤ d ∧ d ≤ 31 ∧ h ≤ 23 ∧ mi ≤ 59 ∧ se ≤ 60 then
      some (((daysFromCivil y mo d * 86400 + h * 3600 + mi * 60 + se) - off) * 1000 + ms)
    else none
  | _ => none

/-- `h:mm AM`, as `Date.formatted(date: .omitted, time: .shortened)` writes it in English
(a narrow no-break space before AM or PM). -/
def shortTime (wall zone : Int) : String :=
  let sod := (wall / 1000 + zone) % 86400
  let h := sod / 3600
  let m := sod / 60 % 60
  let h12 := if h % 12 = 0 then 12 else h % 12
  s!"{h12}:{pad 2 m}\u202F{if h < 12 then "AM" else "PM"}"

#guard dayName 0 == "1970-01-01" && dayName 20749 == "2026-10-23" && dayName (-1) == "1969-12-31"
#guard daysFromCivil 2026 10 23 == 20749 && daysFromCivil 2000 2 29 == 11016
#guard (List.range 3000).all fun i =>
  let d : Int := (i : Int) * 37 - 20000
  let (y, m, dd) := civilFromDays d
  daysFromCivil y m dd == d
#guard parseDayFile "2026-10-23.jsonl" == some 20749 && parseDayFile "2026-02-30.jsonl" == none
#guard parseDayFile "2026-10-23.json" == none && parseDayFile ".DS_Store" == none
#guard iso 1792749600000 == "2026-10-23T10:00:00Z"
#guard parseIso "2026-10-23T10:00:00Z" == some 1792749600000
#guard parseIso "2026-10-23T12:00:00.5+02:00" == some 1792749600500
#guard shortTime 1792749600000 7200 == "12:00\u202FPM" && shortTime 1792749600000 (-36000) == "12:00\u202FAM"
#guard localDay 1792749600000 0 == 20749 && localDay 1792749600000 (-50000) == 20748

end Dates

end Examples.Yap
