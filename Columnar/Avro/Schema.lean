import Init.Data.List

namespace Columnar.Avro

inductive AvroType where
  | null | boolean | int | long | float | double | string | bytes
  | array (elem : AvroType)
  | map (values : AvroType)
  | record (name : String) (fields : List (String × AvroType))
  | union (opts : List AvroType)
  deriving Repr

namespace SchemaJson

private def isWs (c : Char) : Bool :=
  c == ' ' || c == '\n' || c == '\r' || c == '\t'

private def skipWs (s : String) (i : Nat) : Nat :=
  let rec go (j : Nat) : Nat :=
    if h : j < s.length then
      if isWs (s.get ⟨j⟩) then go (j + 1) else j
    else j
  go i

private def peek (s : String) (i : Nat) : Option Char :=
  if h : i < s.length then some (s.get ⟨i⟩) else none

private def bump (i : Nat) : Nat := i + 1

/-- ASCII-only substring `s[lo:hi)` for schema JSON. -/
private def substringRange (s : String) (lo hi : Nat) : String :=
  if lo ≥ hi || hi > s.length then ""
  else Id.run do
    let mut out : String := ""
    let mut k := lo
    while k < hi do
      out := out.push (s.get ⟨k⟩)
      k := k + 1
    out

private def prefixAt (s : String) (i : Nat) (pat : String) : Bool :=
  i + pat.length ≤ s.length &&
    Id.run do
      let mut ok := true
      let mut k := 0
      while k < pat.length do
        if s.get ⟨i + k⟩ != pat.get ⟨k⟩ then ok := false
        k := k + 1
      ok

private def expectChar (s : String) (i : Nat) (c : Char) : Except String Nat :=
  match peek s i with
  | none => throw s!"schema JSON: expected '{c}' at end"
  | some d =>
    if d == c then pure (bump i)
    else throw s!"schema JSON: expected '{c}' got '{d}' at {i}"

private def hex4ToNat (slice : String) : Option Nat :=
  if slice.length != 4 then none
  else
    let rec step (k : Nat) (acc : Nat) : Option Nat :=
      if h : k < 4 then
        let c := slice.get ⟨k⟩
        let v? :=
          if c.isDigit then
            some (c.toNat - '0'.toNat)
          else if c ≥ 'a' && c ≤ 'f' then
            some (10 + (c.toNat - 'a'.toNat))
          else if c ≥ 'A' && c ≤ 'F' then
            some (10 + (c.toNat - 'A'.toNat))
          else none
        match v? with
        | none => none
        | some v => step (k + 1) (acc * 16 + v)
      else
        some acc
    step 0 0

partial def parseStringLitRest (s : String) (i : Nat) : Except String (String × Nat) :=
  let rec go (out : String) (j : Nat) : Except String (String × Nat) :=
    match peek s j with
    | none => throw "schema JSON: unterminated string"
    | some '"' => pure (out, bump j)
    | some '\\' =>
      let j1 := bump j
      match peek s j1 with
      | none => throw "schema JSON: bad escape"
      | some '"' => go (out.push '"') (bump j1)
      | some '\\' => go (out.push '\\') (bump j1)
      | some '/' => go (out.push '/') (bump j1)
      | some 'b' => go (out.push (Char.ofNat 8)) (bump j1)
      | some 'f' => go (out.push (Char.ofNat 12)) (bump j1)
      | some 'n' => go (out.push '\n') (bump j1)
      | some 'r' => go (out.push '\r') (bump j1)
      | some 't' => go (out.push '\t') (bump j1)
      | some 'u' =>
        let j2 := bump j1
        if _ : j2 + 4 ≤ s.length then
          let slice := substringRange s j2 (j2 + 4)
          match hex4ToNat slice.toLower with
          | none => throw "schema JSON: bad unicode escape"
          | some cp => go (out.push (Char.ofNat cp)) (j2 + 4)
        else throw "schema JSON: truncated unicode escape"
      | some c => throw s!"schema JSON: unknown escape '\\{c}'"
    | some c =>
      go (out.push c) (bump j)
  go "" i

private partial def skipJsonValue (s : String) (i : Nat) : Except String Nat := do
  let i := skipWs s i
  match peek s i with
  | some '"' =>
    let (_, j) ← parseStringLitRest s (bump i)
    return j
  | some '{' =>
    let mut j ← expectChar s i '{'
    j := skipWs s j
    while peek s j != some '}' do
      let (_, j1) ← parseStringLitRest s (bump j)
      let j1 ← expectChar s (skipWs s j1) ':'
      j ← skipJsonValue s (skipWs s j1)
      j := skipWs s j
      match peek s j with
      | some ',' => j := bump j
      | some '}' => j := bump j; return j
      | _ => throw "skip: bad object"
    expectChar s j '}'
  | some '[' =>
    let mut j ← expectChar s i '['
    j := skipWs s j
    if peek s j == some ']' then return bump j
    repeat
      j ← skipJsonValue s j
      j := skipWs s j
      match peek s j with
      | some ',' => j := bump j
      | some ']' => return bump j
      | _ => throw "skip: bad array"
    return j
  | some '-' | some '0' | some '1' | some '2' | some '3' | some '4' | some '5' | some '6' | some '7' | some '8' | some '9' =>
    let mut j := i
    while match peek s j with
      | some ch => ch.isDigit || ch == '-' || ch == '+' || ch == '.' || ch == 'e' || ch == 'E'
      | none => false
    do
      j := bump j
    return j
  | some 't' =>
    if prefixAt s i "true" then return i + 4 else throw "skip: bad literal"
  | some 'f' =>
    if prefixAt s i "false" then return i + 5 else throw "skip: bad literal"
  | some 'n' =>
    if prefixAt s i "null" then return i + 4 else throw "skip: bad literal"
  | _ => throw "skip: bad value"

mutual
  /-- Parse `[ fieldObj, ... ]` for record.fields; `i` points at `[`. -/
  partial def parseFieldsArrayCore (s : String) (i : Nat) : Except String (List (String × AvroType) × Nat) := do
    let afterBracket ← expectChar s i '['
    let mut j := skipWs s afterBracket
    if peek s j == some ']' then return ([], bump j)
    let mut acc : List (String × AvroType) := []
    repeat
      let (pair, j2) ← parseFieldObject s j
      acc := acc ++ [pair]
      j := skipWs s j2
      match peek s j with
      | some ',' => j := bump j
      | some ']' => return (acc, bump j)
      | _ => throw "fields: expected ',' or ']'"
    return (acc, j)

  /-- Parse one field object `{ "name": "...", "type": ... }`. -/
  partial def parseFieldObject (s : String) (i : Nat) : Except String ((String × AvroType) × Nat) := do
    let afterBrace ← expectChar s (skipWs s i) '{'
    let mut j := skipWs s afterBrace
    let mut fname : Option String := none
    let mut fty : Option AvroType := none
    while peek s (skipWs s j) != some '}' do
      let j0 := skipWs s j
      let (key, j1) ← parseStringLitRest s (bump j0)
      let j1 ← expectChar s (skipWs s j1) ':'
      let j1 := skipWs s j1
      if key == "name" then
        let (lit, j2) ← parseStringLitRest s (bump j1)
        fname := some lit
        j := skipWs s j2
      else if key == "type" then
        let (t, j2) ← parseType s j1
        fty := some t
        j := skipWs s j2
      else
        j ← skipJsonValue s j1
      match peek s (skipWs s j) with
      | some ',' => j := bump (skipWs s j)
      | some '}' => break
      | _ => throw "field: expected ',' or '}'"
    let jClose ← expectChar s (skipWs s j) '}'
    match fname, fty with
    | some n, some t => return ((n, t), jClose)
    | _, _ => throw "field: missing name or type"

  partial def parseType (s : String) (i : Nat) : Except String (AvroType × Nat) := do
    let i := skipWs s i
    match peek s i with
    | some '"' =>
      let (lit, j) ← parseStringLitRest s (bump i)
      match lit with
      | "null" => return (.null, j)
      | "boolean" => return (.boolean, j)
      | "int" => return (.int, j)
      | "long" => return (.long, j)
      | "float" => return (.float, j)
      | "double" => return (.double, j)
      | "string" => return (.string, j)
      | "bytes" => return (.bytes, j)
      | other => throw s!"schema JSON: unknown primitive {repr other}"
    | some '[' =>
      let i2 ← expectChar s i '['
      let mut j := skipWs s i2
      if peek s j == some ']' then return (.union [], bump j)
      let mut opts : List AvroType := []
      repeat
        let (t, j2) ← parseType s j
        opts := opts ++ [t]
        j := skipWs s j2
        match peek s j with
        | some ',' => j := bump j
        | some ']' => return (.union opts, bump j)
        | _ => throw "schema JSON: union: expected ',' or ']'"
      return (.union opts, j)
    | some '{' =>
      parseBracedAvroType s i
    | _ => throw "schema JSON: type expected"

  /-- Parse `{"type": ...}` composite Avro schema objects (record/array/map/primitive wrapper). -/
  partial def parseBracedAvroType (s : String) (i : Nat) : Except String (AvroType × Nat) := do
    let i0 ← expectChar s i '{'
    let mut j := skipWs s i0
    let mut tyKind : Option String := none
    let mut tyUnion : Option AvroType := none
    let mut rname : Option String := none
    let mut flds : Option (List (String × AvroType)) := none
    let mut arrElem : Option AvroType := none
    let mut mapVals : Option AvroType := none
    while peek s (skipWs s j) != some '}' do
      let j0 := skipWs s j
      let (key, j1) ← parseStringLitRest s (bump j0)
      let j1 ← expectChar s (skipWs s j1) ':'
      let j1 := skipWs s j1
      if key == "type" then
        match peek s j1 with
        | some '[' =>
          let (tv, j2) ← parseType s j1
          tyUnion := some tv
          j := skipWs s j2
        | some '"' =>
          let (lit, j2) ← parseStringLitRest s (bump j1)
          tyKind := some lit
          j := skipWs s j2
        | _ =>
          j ← skipJsonValue s j1
      else if key == "name" then
        let (lit, j2) ← parseStringLitRest s (bump j1)
        rname := some lit
        j := skipWs s j2
      else if key == "fields" then
        let (fs, j2) ← parseFieldsArrayCore s j1
        flds := some fs
        j := skipWs s j2
      else if key == "items" then
        let (elem, j2) ← parseType s j1
        arrElem := some elem
        j := skipWs s j2
      else if key == "values" then
        let (vt, j2) ← parseType s j1
        mapVals := some vt
        j := skipWs s j2
      else
        j ← skipJsonValue s j1
      match peek s (skipWs s j) with
      | some ',' => j := bump (skipWs s j)
      | some '}' => break
      | _ => throw "schema JSON: expected ',' or '}'"
    let jend ← expectChar s (skipWs s j) '}'
    match tyUnion with
    | some u => return (u, jend)
    | none =>
      match tyKind with
      | none => throw "schema JSON: missing type"
      | some "record" =>
        match rname, flds with
        | some n, some fs => return (.record n fs, jend)
        | _, _ => throw "schema JSON: record needs name and fields"
      | some "array" =>
        match arrElem with
        | none => throw "schema JSON: array needs items"
        | some e => return (.array e, jend)
      | some "map" =>
        match mapVals with
        | none => throw "schema JSON: map needs values"
        | some v => return (.map v, jend)
      | some "null" => return (.null, jend)
      | some "boolean" => return (.boolean, jend)
      | some "int" => return (.int, jend)
      | some "long" => return (.long, jend)
      | some "float" => return (.float, jend)
      | some "double" => return (.double, jend)
      | some "string" => return (.string, jend)
      | some "bytes" => return (.bytes, jend)
      | some other => throw s!"schema JSON: unknown type keyword {repr other}"
end

private def lstripAscii (s : String) (i : Nat) : Nat :=
  if h : i < s.length then
    if isWs (s.get ⟨i⟩) then lstripAscii s (i + 1) else i
  else i

private partial def rstripAscii (s : String) (j : Nat) : Nat :=
  if j == 0 then 0
  else
    let k := j - 1
    if h : k < s.length then
      if isWs (s.get ⟨k⟩) then rstripAscii s k else j
    else j

private def trimAscii (s : String) : String :=
  let lo := lstripAscii s 0
  let hi := rstripAscii s s.length
  if lo ≥ hi then "" else substringRange s lo hi

def parseSchemaJsonString (s : String) : Except String AvroType := do
  let s := trimAscii s
  let (t, j) ← parseType s (skipWs s 0)
  if skipWs s j < s.length then throw "schema JSON: trailing junk"
  return t

end SchemaJson

def parseSchemaJsonString := Columnar.Avro.SchemaJson.parseSchemaJsonString

end Columnar.Avro
