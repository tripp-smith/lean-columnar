import Init.Data.Int
import Init.System.FilePath
import Columnar.Parquet.Encoding.Plain
import Columnar.Table

open Columnar
open Columnar.Parquet.Encoding.Plain

namespace Tests.GoldenFmt

structure ParsedGolden where
  column : String
  kindStr : String
  rows : Array String

def trimLines (s : String) : List String :=
  (s.splitOn "\n").foldl (fun acc part =>
      let t := (String.trimAscii part).toString
      if t.isEmpty then acc else acc ++ [t]) []

def parseFileContents (pathLabel : String) (txt : String) : Except String ParsedGolden :=
  match trimLines txt with
  | col :: kind :: payloads =>
      return { column := col, kindStr := kind, rows := payloads.toArray }
  | _ =>
      throw s!"golden {pathLabel}: need column line, kind line, payload lines"

def parseFile (relative : System.FilePath) : IO (Except String ParsedGolden) := do
  let txt ← IO.FS.readFile relative
  return parseFileContents relative.toString txt

def byteArraySingletonNat (b : ByteArray) : Option Nat :=
  if _ : b.size = 1 then
    some (UInt8.toNat <| b[(0 : Nat)]!)
  else
    none

def cellAsGoldenString (pv : PlainValue) : String :=
  match pv with
  | .bool b => if b then "1" else "0"
  | .int32 n => n.toInt.repr
  | .int64 n => n.toInt.repr
  | .byteArray b =>
      match byteArraySingletonNat b with
      | none => "<<multi_byte_array>>"
      | some n => n.repr
  | _ => "<<unsupported_plain_value_kind>>"

def columnByName (t : Table) (name : String) : Option Column :=
  t.columns.find? fun col => col.name == name

def goldenMatches (t : Table) (g : ParsedGolden) : Except String Unit :=
  match columnByName t g.column with
  | none => throw s!"column «{g.column}» not found"
  | some col =>
    if col.values.size != g.rows.size then
      throw s!"«{g.column}» length mismatch {col.values.size}≠{g.rows.size}"
    else do
      for idx in [:col.values.size] do
        match col.values[idx]? with
        | none => throw s!"row {idx}: indexing failed"
        | some none => throw s!"row {idx}: null cell"
        | some (some pv) =>
          match g.rows[idx]? with
          | none => throw s!"row {idx}: golden OOB"
          | some raw =>
            let gs := (String.trimAscii raw).toString
            unless cellAsGoldenString pv == gs do
              throw s!"row {idx}: «{g.column}» got {cellAsGoldenString pv} want {gs}"
            pure ()
      return ()

end Tests.GoldenFmt
