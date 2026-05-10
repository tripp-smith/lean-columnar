import Init.Data.Int
import Columnar.Core.Result
import Columnar.Parquet.Metadata

/-! Preorder parquet schema → column chunks (matching `ColumnChunk` order) plus level bounds. -/

namespace Columnar.Parquet.SchemaWalk

structure ColumnLeaf where
  /-- Fully qualified path dotted (matches pyarrow chunk path strings). -/
  pathName : String
  /-- Path segments excluding synthetic root column name where empty. -/
  pathParts : Array String
  elt : SchemaElement
  phys : Nat
  /-- Max definition/repetition level for decoding data pages v1 (`def` slice then `rep` slice then values). -/
  maxDefinitionLevel : Nat
  maxRepetitionLevel : Nat

def applyRepetition (rep : Option Nat) (inhDef inhRep : Nat) : Nat × Nat :=
  match rep with
  | none | some 0 => (inhDef, inhRep)
  | some 1 => (inhDef + 1, inhRep)
  | some 2 => (inhDef + 1, inhRep + 1)
  | some _ => (inhDef, inhRep) -- unknown sentinel; behave like REQUIRED rather than falsely bumping REP

abbrev P := Except String

def childrenCount (e : SchemaElement) : Nat :=
  match e.numChildren with
  | none => 0
  | some k => Int.natAbs (Int32.toInt k)

def joinParts (pfx : Array String) (nm : String) : Array String :=
  if nm.isEmpty then pfx else pfx.push nm

def dotJoinPath (parts : Array String) : String :=
  parts.foldl (fun acc s =>
    if acc.isEmpty then s else acc ++ "." ++ s) ""

partial def preorderNode (schema : Array SchemaElement) (idx : Nat) (pathPrefix : Array String)
    (inheritDef inheritRep : Nat) : P (Array ColumnLeaf × Nat) :=
  if h : idx < schema.size then
    let e := schema[idx]'h
    match e.physType with
    | some phy =>
      let nm := e.name.getD ""
      let parts := joinParts pathPrefix nm
      let pathStr := dotJoinPath parts
      let (mdl, mrl) := applyRepetition e.repetition inheritDef inheritRep
      pure (#[{ pathName := pathStr, pathParts := parts,
                elt := e, phys := phy, maxDefinitionLevel := mdl, maxRepetitionLevel := mrl }], idx + 1)
    | none => do
      let grp := e.name.getD ""
      let pathBase := joinParts pathPrefix grp
      let nc := childrenCount e
      let (innerDef, innerRep) := applyRepetition e.repetition inheritDef inheritRep
      let mut j := idx + 1
      let mut accum : Array ColumnLeaf := #[]
      for _ in [:nc] do
        let (xs, j') ← preorderNode schema j pathBase innerDef innerRep
        accum := accum ++ xs
        j := j'
      pure (accum, j)
  else
    throw "SchemaWalk: index out of range"

/-- Skip `schema[0]` (protocol root element) if it is synthetic; recurse from first logical child index. -/
def preorderLeavesFromSchema (schema : Array SchemaElement) : P (Array ColumnLeaf) := do
  if schema.size == 0 then throw "SchemaWalk: empty schema"
  let rootIdx : Nat := 0
  if h : rootIdx < schema.size then
    let root := schema[rootIdx]'h
    match root.physType with
    | some _ =>
      let (xs, _) ← preorderNode schema 0 #[] 0 0
      pure xs
    | none => do
      let nc := childrenCount root
      let (innerDef, innerRep) := applyRepetition root.repetition 0 0
      let mut j : Nat := 1
      let mut out : Array ColumnLeaf := #[]
      for _ in [:nc] do
        let (xs, j') ← preorderNode schema j #[] innerDef innerRep
        out := out ++ xs
        j := j'
      pure out
  else
    throw "SchemaWalk: invalid root"

/-- Match `leaf.pathName` dotted to `chunk.path.last` parity: compare joined column path segments. -/
def leafMatchesChunkPath (leaf : ColumnLeaf) (chunkPath : Array String) : Bool :=
  leaf.pathParts == chunkPath

def matchLeavesToChunks (leaves : Array ColumnLeaf) (chunks : Array ColumnChunkParsed)
    : P (Array ColumnLeaf) := do
  if leaves.size != chunks.size then
    throw s!"schema/chunk arity mismatch leaves={leaves.size} chunks={chunks.size}"
  let mut paired : Array ColumnLeaf := #[]
  for pr in chunks.zip leaves do
    let (chunk, leaf) := pr
    if leaf.pathParts != chunk.columnMeta.path then
      throw s!"path mismatch leaf={repr leaf.pathParts} chunk={repr chunk.columnMeta.path}"
    paired := paired.push leaf
  pure paired

/-- When chunk order differs from preorder leaf order, pair by dotted path (chunk order wins). -/
def matchLeavesToChunksByPath (leaves : Array ColumnLeaf) (chunks : Array ColumnChunkParsed)
    : P (Array ColumnLeaf) := do
  if leaves.size != chunks.size then
    throw s!"schema/chunk arity mismatch leaves={leaves.size} chunks={chunks.size}"
  let mut paired : Array ColumnLeaf := #[]
  for chunk in chunks do
    let p := chunk.columnMeta.path
    match leaves.find? fun lf => lf.pathParts == p with
    | none => throw s!"no schema leaf for chunk path {repr p}"
    | some leaf => paired := paired.push leaf
  pure paired

end Columnar.Parquet.SchemaWalk
