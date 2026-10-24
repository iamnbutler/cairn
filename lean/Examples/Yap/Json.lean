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

/-- A number: `-`? digits (no leading zero), then optionally a fraction and an exponent. -/
def number (cs : List Char) : Option (Json × List Char) :=
  let (neg, cs) := match cs with
    | '-' :: r => (true, r)
    | r => (false, r)
  let ds := cs.takeWhile isDigit
  if ds.isEmpty then none
  else if ds.head? = some '0' ∧ 1 < ds.length then none
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

/-- How deep arrays and objects may nest: `JSONDecoder` gives up past 512. -/
def maxDepth : Nat := 512

mutual
/-- A value, then what follows it. `fuel` bounds the work (the input's length is enough);
`depth` is how many arrays and objects enclose it. -/
def value : Nat → Nat → List Char → Option (Json × List Char)
  | 0, _, _ => none
  | fuel + 1, depth, cs =>
    match skipWs cs with
    | '{' :: rest => if depth < maxDepth then members fuel (depth + 1) [] (skipWs rest) true else none
    | '[' :: rest => if depth < maxDepth then elements fuel (depth + 1) [] (skipWs rest) true else none
    | '"' :: rest => (strBody (rest.length + 1) [] rest).map fun (s, r) => (.str s, r)
    | 't' :: 'r' :: 'u' :: 'e' :: rest => some (.bool true, rest)
    | 'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest => some (.bool false, rest)
    | 'n' :: 'u' :: 'l' :: 'l' :: rest => some (.null, rest)
    | cs' => number cs'

/-- An object's members after `{`, newest first in `acc`. As in `JSONDecoder`, one comma may
follow the last member. -/
def members : Nat → Nat → List (String × Json) → List Char → Bool → Option (Json × List Char)
  | 0, _, _, _, _ => none
  | fuel + 1, depth, acc, cs, first =>
    match cs with
    | '}' :: rest => if first then some (.obj [], rest) else some (.obj acc.reverse, rest)
    | '"' :: rest =>
      match strBody (rest.length + 1) [] rest with
      | none => none
      | some (k, rest) =>
        match skipWs rest with
        | ':' :: rest =>
          match value fuel depth rest with
          | none => none
          | some (v, rest) =>
            match skipWs rest with
            | ',' :: rest => members fuel depth ((k, v) :: acc) (skipWs rest) false
            | '}' :: rest => some (.obj ((k, v) :: acc).reverse, rest)
            | _ => none
        | _ => none
    | _ => none

/-- An array's elements after `[`; one comma may follow the last. -/
def elements : Nat → Nat → List Json → List Char → Bool → Option (Json × List Char)
  | 0, _, _, _, _ => none
  | fuel + 1, depth, acc, cs, first =>
    match cs with
    | ']' :: rest => if first then some (.arr [], rest) else some (.arr acc.reverse, rest)
    | cs =>
      match value fuel depth cs with
      | none => none
      | some (v, rest) =>
        match skipWs rest with
        | ',' :: rest => elements fuel depth (v :: acc) (skipWs rest) false
        | ']' :: rest => some (.arr (v :: acc).reverse, rest)
        | _ => none
end

/-- A whole document: one value and nothing after it but white space. -/
def parse (s : String) : Option Json :=
  let cs := s.toList
  match value (cs.length + 1) 0 cs with
  | some (v, rest) => if skipWs rest = [] then some v else none
  | none => none

/-! ### Bytes

`JSONDecoder` reads UTF-8 (a byte order mark is skipped), and UTF-16 or UTF-32 when a byte
order mark or the zero bytes of the first characters say so. -/

/-- Big-endian (or little-endian) 16-bit units, an odd last byte dropped. -/
def units16 (be : Bool) : List UInt8 → List Nat
  | a :: b :: rest => (if be then a.toNat * 256 + b.toNat else b.toNat * 256 + a.toNat) :: units16 be rest
  | _ => []

def units32 (be : Bool) : List UInt8 → List Nat
  | a :: b :: c :: d :: rest =>
    (if be then ((a.toNat * 256 + b.toNat) * 256 + c.toNat) * 256 + d.toNat
     else ((d.toNat * 256 + c.toNat) * 256 + b.toNat) * 256 + a.toNat) :: units32 be rest
  | _ => []

/-- UTF-16 units as characters: none for a surrogate out of its pair. -/
def fromUtf16 : List Nat → Option (List Char)
  | [] => some []
  | u :: rest =>
    if 0xD800 ≤ u ∧ u < 0xDC00 then
      match rest with
      | l :: rest' =>
        if 0xDC00 ≤ l ∧ l < 0xE000 then
          (fromUtf16 rest').map (Char.ofNat (0x10000 + (u - 0xD800) * 0x400 + (l - 0xDC00)) :: ·)
        else none
      | [] => none
    else if 0xDC00 ≤ u ∧ u < 0xE000 then none
    else (fromUtf16 rest).map (Char.ofNat u :: ·)

def fromUtf32 (us : List Nat) : Option (List Char) :=
  us.mapM fun u => if u < 0x110000 ∧ !(0xD800 ≤ u ∧ u < 0xE000) then some (Char.ofNat u) else none

/-- The text of a JSON document's bytes, as `JSONDecoder` finds its encoding. -/
def text (d : ByteArray) : Option String :=
  let bs := d.toList
  let u16 (be : Bool) (skip : Nat) := (fromUtf16 (units16 be (bs.drop skip))).map String.ofList
  let u32 (be : Bool) (skip : Nat) := (fromUtf32 (units32 be (bs.drop skip))).map String.ofList
  if 4 ≤ bs.length then
    match bs with
    | 0 :: 0 :: 0xFE :: 0xFF :: _ => u32 true 4
    | 0xFE :: 0xFF :: _ => u16 true 2
    | 0xFF :: 0xFE :: _ => u16 false 2
    | 0 :: 0 :: 0 :: _ => u32 true 0
    | _ :: 0 :: 0 :: 0 :: _ => u32 false 0
    | 0 :: _ => u16 true 0
    | _ :: 0 :: _ => u16 false 0
    | 0xEF :: 0xBB :: 0xBF :: rest => String.fromUTF8? (ByteArray.mk rest.toArray)
    | _ => String.fromUTF8? d
  else
    match bs with
    | 0xFE :: 0xFF :: _ => u16 true 2
    | 0xFF :: 0xFE :: _ => u16 false 2
    | 0 :: _ :: _ => u16 true 0
    | _ :: 0 :: _ => u16 false 0
    | _ => String.fromUTF8? d

/-- A document from its bytes. -/
def parseBytes (d : ByteArray) : Option Json := (text d).bind parse

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

def int64Min : Int := -9223372036854775808
def int64Max : Int := 9223372036854775807

/-- A run of decimal digits: none if empty. -/
def natDigits (cs : List Char) : Option Nat :=
  if !cs.isEmpty ∧ cs.all isDigit then some (cs.foldl (fun n c => n * 10 + (c.toNat - '0'.toNat)) 0)
  else none

/-- `n / d` rounded to the nearest integer, ties to even. -/
def roundHalfEven (n d : Nat) : Nat :=
  let q := n / d
  let r := n % d
  if 2 * r < d then q else if d < 2 * r then q + 1 else if q % 2 = 0 then q else q + 1

/-- The double nearest `n / d` (positive, at least 1/10 and below 10^20) as `q * 2^k`, with
`2^52 ≤ q < 2^53`. -/
def nearestDouble (n d : Nat) : Nat × Int :=
  let scaled (k : Int) : Nat × Nat :=
    if 0 ≤ k then (n, d * 2 ^ k.toNat) else (n * 2 ^ (-k).toNat, d)
  let k := ((List.range 140).map fun (i : Nat) => (i : Int) - 70).find? fun k =>
    let (a, b) := scaled k
    2 ^ 52 * b ≤ a ∧ a < 2 ^ 53 * b
  let k := k.getD 0
  let (a, b) := scaled k
  let q := roundHalfEven a b
  if q = 2 ^ 53 then (2 ^ 52, k + 1) else (q, k)

/-- What `JSONDecoder` makes of a number with a fraction or an exponent read as an `Int`: the
nearest double, when it is a whole number that fits in 64 bits. -/
def numInt (t : String) : Option Int := do
  let cs := t.toList
  let (neg, cs) := match cs with
    | '-' :: r => (true, r)
    | r => (false, r)
  let ds := cs.takeWhile isDigit
  let cs := cs.dropWhile isDigit
  let (fs, cs) := match cs with
    | '.' :: r => (r.takeWhile isDigit, r.dropWhile isDigit)
    | r => ([], r)
  let ex : Int ← match cs with
    | [] => some 0
    | e :: r =>
      if e = 'e' ∨ e = 'E' then
        match r with
        | '+' :: r' => (natDigits r').map Int.ofNat
        | '-' :: r' => (natDigits r').map fun n => -(n : Int)
        | r' => (natDigits r').map Int.ofNat
      else none
  let m := (ds ++ fs).foldl (fun n c => n * 10 + (c.toNat - '0'.toNat)) 0
  let e := ex - fs.length
  if m = 0 then return 0
  -- The magnitude is about 10^(mag): at least 10^20 is out of range, below 10^-400 is zero.
  let mag : Int := (toString m).length - 1 + e
  if 20 ≤ mag then none
  else if mag < -400 then return 0
  else
    let (n, d) : Nat × Nat := if 0 ≤ e then (m * 10 ^ e.toNat, 1) else (m, 10 ^ (-e).toNat)
    if n * 2 ^ 1075 ≤ d then return 0  -- rounds to zero
    else if 10 * n < d then none  -- below 1/10: never a whole number
    else
      let (q, k) := nearestDouble n d
      let v : Int ← if 0 ≤ k then some ((q * 2 ^ k.toNat : Nat) : Int)
        else if q % 2 ^ (-k).toNat = 0 then some ((q / 2 ^ (-k).toNat : Nat) : Int) else none
      let v := if neg then -v else v
      if int64Min ≤ v ∧ v ≤ int64Max then some v else none

/-- An `Int` as `JSONDecoder` reads one: a whole number in 64 bits, or a number with a fraction
or exponent whose nearest double is one. -/
def Json.getInt : Json → Option Int
  | .int n => if int64Min ≤ n ∧ n ≤ int64Max then some n else none
  | .num t => numInt t
  | _ => none

/-! ## Writing -/

def hexDigit (n : Nat) : Char := if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

/-- A string literal as `JSONEncoder` writes it: `"` and `\` escaped, `/` too unless
`.withoutEscapingSlashes` (`slash := false`), the control characters as `\n`, `\t`, … or
`\u00xx`, everything else as it is. -/
def quote (s : String) (slash : Bool := false) : String :=
  let body := s.toList.flatMap fun c =>
    if c = '"' then ['\\', '"']
    else if slash ∧ c = '/' then ['\\', '/']
    else if c = '\\' then ['\\', '\\']
    else if c = '\n' then ['\\', 'n']
    else if c = '\r' then ['\\', 'r']
    else if c = '\t' then ['\\', 't']
    else if c = '\x08' then ['\\', 'b']
    else if c = '\x0c' then ['\\', 'f']
    else if c.toNat < 0x20 then ['\\', 'u', '0', '0', hexDigit (c.toNat / 16), hexDigit (c.toNat % 16)]
    else [c]
  "\"" ++ String.ofList body ++ "\""

def scalar (slash : Bool := false) : Json → String
  | .null => "null"
  | .bool b => if b then "true" else "false"
  | .int n => toString n
  | .num t => t
  | .str s => quote s slash
  | .arr _ | .obj _ => "null"

/-- A flat object, compact, keys as given (callers give them sorted). -/
def compact (kvs : List (String × Json)) : String :=
  "{" ++ ",".intercalate (kvs.map fun (k, v) => quote k ++ ":" ++ scalar false v) ++ "}"

/-- A flat object as `JSONEncoder` writes it with `.prettyPrinted` (and without
`.withoutEscapingSlashes`, so `/` is `\/`): two-space indent and `" : "`, keys as given. -/
def pretty (kvs : List (String × Json)) : String :=
  if kvs.isEmpty then "{\n\n}"
  else "{\n" ++ ",\n".intercalate (kvs.map fun (k, v) => "  " ++ quote k true ++ " : " ++ scalar true v) ++ "\n}"

#guard (parse "{\"text\":\"Hello, world.\",\"usage\":{\"type\":\"tokens\",\"total_tokens\":12.5e1}}" |>.bind (·.field "text") |>.bind Json.getStr) == some "Hello, world."
#guard (parse "{ \"a\" : [1, -2, {\"b\": null}], \"c\": \"\\u00e9\\ud83d\\ude00\\n\" }" |>.bind (·.field "c") |>.bind Json.getStr) == some "é😀\n"
#guard (parse "[1 2]").isNone && (parse "{\"a\":1} x").isNone
-- `JSONDecoder`'s leniencies and limits (each checked against it, docs/yap-parity.md).
#guard (parse "{\"a\":1,}").isSome && (parse "[1,]").isSome && (parse "{\"a\":1 , }").isSome
#guard (parse "[1,,]").isNone && (parse "{,}").isNone && (parse "[,1]").isNone && (parse "[1,]]").isNone
#guard (parse "01").isNone && (parse "-01").isNone && (parse "1.").isNone && (parse "+1").isNone
#guard (parse ".5").isNone && (parse "/* c */{}").isNone && (parse "\"\\U0041\"").isNone
#guard (parse "0e5").isSome && (parse "-0").isSome && (parse "\"a\\u0000b\"").isSome
#guard (parse ("{\"a\":" ++ String.ofList (List.replicate 511 '[') ++ String.ofList (List.replicate 511 ']') ++ "}")).isSome
#guard (parse ("{\"a\":" ++ String.ofList (List.replicate 512 '[') ++ String.ofList (List.replicate 512 ']') ++ "}")).isNone
#guard (parse (String.ofList (List.replicate 512 '[') ++ String.ofList (List.replicate 512 ']'))).isSome
#guard (parse (String.ofList (List.replicate 513 '[') ++ String.ofList (List.replicate 513 ']'))).isNone
-- Whole numbers as `Int`: exact up to 64 bits; otherwise through the nearest double.
#guard ["30.0", "1e1", "-0", "1E2", "2.0e0", "100e-2", "1.5e1", "0.0", "-0.0", "1.0000000000000000001",
    "9223372036854775807", "-9223372036854775808", "0e999999999", "1e-400"].map (fun t => (parse t).bind Json.getInt)
  == [some 30, some 10, some 0, some 100, some 2, some 1, some 15, some 0, some 0, some 1,
      some 9223372036854775807, some (-9223372036854775808), some 0, some 0]
#guard ["30.5", "99999999999999999999", "9223372036854775808", "9223372036854775807.0", "1e400",
    "-9223372036854775809", "5e-1", "1e-300"].all fun t => ((parse t).bind Json.getInt).isNone
#guard ((parse "-9223372036854775808.0").bind Json.getInt) == some (-9223372036854775808)
#guard ((parse "9007199254740993.0").bind Json.getInt) == some 9007199254740992
#guard (parse "\"\\ud800\"").isNone
#guard compact [("app", .str "Notes"), ("date", .str "2026-10-23T10:00:00Z"), ("text", .str "a \"b\"/c"), ("typed", .bool false)]
  == "{\"app\":\"Notes\",\"date\":\"2026-10-23T10:00:00Z\",\"text\":\"a \\\"b\\\"/c\",\"typed\":false}"
#guard pretty [("key", .str "a/b\"é\x01"), ("retentionDays", .int (-4))]
  == "{\n  \"key\" : \"a\\/b\\\"é\\u0001\",\n  \"retentionDays\" : -4\n}"
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

/-- Up to `max` ASCII digits (at least one): their value, how many, and what follows. -/
def isoDigits (max : Nat) (cs : List Char) : Option (Nat × Nat × List Char) :=
  let ds := (cs.takeWhile Json.isDigit).take max
  if ds.isEmpty then none
  else some (ds.foldl (fun n c => n * 10 + (c.toNat - 48)) 0, ds.length, cs.drop ds.length)

def isoExpect (c : Char) : List Char → Option (List Char)
  | x :: rest => if x = c then some rest else none
  | [] => none

/-- The Julian day number (noon-based) of day 0 of `month` in `year` (the day before the 1st),
in the Julian or the Gregorian calendar (Richards' algorithm, as Foundation's
`_CalendarGregorian.julianDay(ofDay:month:year:useJulianReference:)` computes it, with Swift's
truncating division). -/
def julianDay (day month year : Int) (julian : Bool) : Int :=
  let h := month - 2
  let g := (year + 4716) - (12 - h).tdiv 12
  let f := (h - 1 + 12).tmod 12
  let e := (1461 * g).tdiv 4 + day - 1 - 1401
  let j := e + (153 * f + 2).tdiv 5
  if julian then j else j - (3 * (g + 184).tdiv 100).tdiv 4 + 38

/-- The time zone at the end of an ISO 8601 date-time: its offset in seconds east of UTC. -/
def isoZone (cs : List Char) : Option Int :=
  let digitsAfter (positive : Bool) (cs : List Char) : Option Int := do
    let (hours, _, cs) ← isoDigits 2 cs
    let (expectMinutes, cs) := match cs with
      | ':' :: r => (true, r)
      | c :: r => (Json.isDigit c, c :: r)
      | [] => (false, [])
    let off ← if !expectMinutes then some (hours * 3600)
      else do
        let (minutes, _, cs) ← isoDigits 2 cs
        let cs := match cs with
          | ':' :: r => r
          | r => r
        match cs with
        | c :: _ =>
          if Json.isDigit c then
            let (seconds, _, _) ← isoDigits 2 cs
            some (hours * 3600 + minutes * 60 + seconds)
          else some (hours * 3600 + minutes * 60)
        | [] => some (hours * 3600 + minutes * 60)
    -- `TimeZone(secondsFromGMT:)` takes at most 18 hours either way.
    if off = 0 then some 0 else if off ≤ 18 * 3600 then some (if positive then (off : Int) else -(off : Int)) else none
  let named (cs : List Char) : Option Int :=
    match cs with
    | '+' :: r => digitsAfter true r
    | '-' :: r => digitsAfter false r
    | _ => some 0
  match cs with
  | [] => none
  | c :: rest =>
    if c = 'Z' ∨ c = 'z' then some 0
    else if c = 'G' ∨ c = 'g' then
      match rest with
      | m :: t :: r => if (m = 'M' ∨ m = 'm') ∧ (t = 'T' ∨ t = 't') then named r else none
      | _ => none
    else if c = 'U' ∨ c = 'u' then
      match rest with
      | t :: c' :: r => if (t = 'T' ∨ t = 't') ∧ (c' = 'C' ∨ c' = 'c') then named r else none
      | _ => none
    else if c = '+' then digitsAfter true rest
    else if c = '-' then digitsAfter false rest
    else none

/-- Wall milliseconds of an ISO 8601 date-time, as `JSONDecoder`'s `.iso8601` reads one
(Foundation's `Date.ISO8601FormatStyle` of Swift 6.2: `YYYY-MM-DDTHH:MM:SS`, each field one to
ten digits, the month 1–12 and the day 1–31 but the time unchecked, so it rolls over; an
optional fraction of one to nine digits; then `Z`, `GMT` or `UTC`, or an offset `±H`, `±HHMM`,
`±HH:MM` or `±HH:MM:SS`, within 18 hours; anything after that is ignored). Dates before
1582-10-15 are in the Julian calendar, as in Foundation's Gregorian calendar. -/
def parseIso (s : String) : Option Int := do
  let cs := s.toList
  let (y, _, cs) ← isoDigits 10 cs
  let cs ← isoExpect '-' cs
  let (mo, _, cs) ← isoDigits 10 cs
  if mo < 1 ∨ 12 < mo then none
  let cs ← isoExpect '-' cs
  let (d, _, cs) ← isoDigits 10 cs
  if d < 1 ∨ 31 < d then none
  let cs ← isoExpect 'T' cs
  let (h, _, cs) ← isoDigits 10 cs
  let cs ← isoExpect ':' cs
  let (mi, _, cs) ← isoDigits 10 cs
  let cs ← isoExpect ':' cs
  let (se, _, cs) ← isoDigits 10 cs
  let (nanos, cs) ← match cs with
    | '.' :: r => do
      let (f, n, r) ← isoDigits 10 r
      if 9 < n then none
      some (f * 10 ^ (9 - n), r)
    | r => some (0, r)
  let off ← isoZone cs
  -- `_CalendarGregorian.isComponentsInSupportedRange`
  if 506714 < y ∨ 2147483647 < h ∨ 2147483647 < mi ∨ 2147483647 < se then none
  let jd := julianDay 0 mo y false + d
  let jd := if jd < 2299161 then julianDay 0 mo y true + d else jd
  some (((jd - 2440588) * 86400 + h * 3600 + mi * 60 + se - off) * 1000 + (nanos / 1000000 : Nat))

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
