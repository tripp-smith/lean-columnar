import Init.Data.ByteArray
import Init.System.FilePath
import Columnar.Core.Bytes
import Columnar.Arrow.Flatbuf
import Columnar.Parquet.Encoding.Plain
import Columnar.Table

namespace Columnar.Arrow.IPC

open Columnar
open Columnar.ByteArrayOps
open Columnar.Arrow.Flatbuf
open Columnar.Parquet.Encoding.Plain

abbrev P := Except String

def align8 (n : Nat) : Nat :=
  (n + 7) / 8 * 8

/-- IPC stream framing often starts with the continuation sentinel word (little-endian UInt32 `-1`). -/
def ipcStreamLooksFramed (pfx : ByteArray) : Bool :=
  match readUInt32LE pfx 0 with
  | none => false
  | some w => w == 0xffffffff

/-- Parse `Message.bodyLength` from an IPC metadata flatbuffer (root type `Message`). -/
def messageBodyLength (md : ByteArray) : P Nat := do
  let rootU ← match readUInt32LE md 0 with
    | none => throw "Arrow IPC: metadata missing root offset"
    | some u => pure u.toNat
  let obj := rootU
  let vt ← match tableVtable md obj with
    | none => throw "Arrow IPC: Message vtable"
    | some x => pure x
  let (vs, _) ← match vtableSizes md vt with
    | none => throw "Arrow IPC: vtable sizes"
    | some x => pure x
  let n := vtableFieldSlotCount vs
  if n ≤ 3 then pure 0
  else
    match vtableFieldOffset md vt 3 with
    | none => pure 0
    | some fo =>
      let addr := fieldAddr obj fo
      match readInt64LE md addr with
      | none => throw "Arrow IPC: bodyLength"
      | some bl =>
        let i := Int64.toInt bl
        if i < 0 then throw "Arrow IPC: negative bodyLength"
        else pure i.natAbs

/-- Count IPC **stream** messages (excluding a trailing EOS marker with `metadata_length == 0`). -/
partial def ipcStreamMessageCount (b : ByteArray) : P Nat :=
  let rec go (pos : Nat) (cnt : Nat) : P Nat :=
    if pos ≥ b.size then pure cnt
    else if pos + 8 > b.size then throw "Arrow IPC: truncated message header"
    else
      match readUInt32LE b pos with
      | none => throw "Arrow IPC: read u32"
      | some cont =>
        let p0 := if cont == 0xffffffff then pos + 4 else pos
        if p0 + 4 > b.size then throw "Arrow IPC: truncated length"
        else
          match readInt32LE b p0 with
          | none => throw "Arrow IPC: read i32"
          | some mlen32 =>
            let mlenI := Int32.toInt mlen32
            if mlenI < 0 then throw "Arrow IPC: negative metadata length"
            else
              let mlen := Int.natAbs mlenI
              if mlen == 0 then pure cnt
              else
                let metaStart := p0 + 4
                if metaStart + mlen > b.size then throw "Arrow IPC: truncated metadata payload"
                else do
                  let md := b.extract metaStart (metaStart + mlen)
                  let bodyLen ← messageBodyLength md
                  let afterMeta := metaStart + mlen
                  let bodyOff := align8 afterMeta
                  if bodyOff + bodyLen > b.size then throw "Arrow IPC: truncated body"
                  else go (bodyOff + bodyLen) (cnt + 1)
  go 0 0

/-- `org.apache.arrow.flatbuf.MessageHeader` union discriminant: `Schema` = 1, `RecordBatch` = 3. -/
def messageHeaderSchema : UInt8 := 1
def messageHeaderRecordBatch : UInt8 := 3

/-- `org.apache.arrow.flatbuf.Type` union discriminant for `Int` = 2. -/
def typeUnionInt : UInt8 := 2
def typeUnionBool : UInt8 := 6
def typeUnionFloatingPoint : UInt8 := 3
def typeUnionBinary : UInt8 := 4
def typeUnionUtf8 : UInt8 := 5

inductive ArrowColKind where
  | int32 | int64 | bool | float | double | utf8 | binary

structure ArrowColSpec where
  name : String
  kind : ArrowColKind

def parseIntType (md : ByteArray) (obj : Nat) : P (Bool × Nat) := do
  let vt ← match tableVtable md obj with
    | none => throw "Arrow IPC: Int vtable"
    | some x => pure x
  let bw ← match vtableFieldOffset md vt 0 with
    | none => throw "Arrow IPC: Int.bitWidth missing"
    | some fo =>
      match readInt32LE md (fieldAddr obj fo) with
      | none => throw "Arrow IPC: Int.bitWidth"
      | some w => pure (Int32.toInt w).natAbs
  let signed ← match vtableFieldOffset md vt 1 with
    | none => pure true
    | some fo =>
      let a := fieldAddr obj fo
      if a ≥ md.size then throw "Arrow IPC: Int.is_signed"
      else pure (md[a]! != 0)
  pure (signed, bw)

def parseFieldType (md : ByteArray) (fieldObj : Nat) : P ArrowColKind := do
  let vt ← match tableVtable md fieldObj with
    | none => throw "Arrow IPC: Field vtable"
    | some x => pure x
  let typeDiscAddr ← match vtableFieldOffset md vt 2 with
    | none => throw "Arrow IPC: Field.type (discriminator) missing"
    | some fo => pure (fieldAddr fieldObj fo)
  if typeDiscAddr ≥ md.size then throw "Arrow IPC: Field.type disc OOB"
  let disc := md[typeDiscAddr]!
  let typeTableSlot ← match vtableFieldOffset md vt 3 with
    | none => throw "Arrow IPC: Field.type (table) missing"
    | some fo => pure (fieldAddr fieldObj fo)
  if disc == typeUnionInt then
    let tu ← match followUOffset md typeTableSlot with
      | none => throw "Arrow IPC: Int type offset"
      | some tObj => pure tObj
    let (_s, bw) ← parseIntType md tu
    if bw == 32 then pure .int32
    else if bw == 64 then pure .int64
    else throw s!"Arrow IPC: unsupported Int bitWidth {bw}"
  else if disc == typeUnionBool then pure .bool
  else if disc == typeUnionFloatingPoint then
    let tu ← match followUOffset md typeTableSlot with
      | none => throw "Arrow IPC: FloatingPoint offset"
      | some tObj => pure tObj
    let fvt ← match tableVtable md tu with
      | none => throw "Arrow IPC: FloatingPoint vtable"
      | some x => pure x
    match vtableFieldOffset md fvt 0 with
    | none => throw "Arrow IPC: FloatingPoint.precision"
    | some fo =>
      match readInt16LE md (fieldAddr tu fo) with
      | none => throw "Arrow IPC: FloatingPoint.precision read"
      | some pr =>
        let p := Int16.toInt pr
        if p == 1 then pure .float -- SINGLE
        else if p == 2 then pure .double -- DOUBLE
        else throw "Arrow IPC: unsupported FloatingPoint precision (HALF not implemented)"
  else if disc == typeUnionUtf8 then pure .utf8
  else if disc == typeUnionBinary then pure .binary
  else throw s!"Arrow IPC: unsupported Field.type discriminator {disc.toNat}"

def parseSchemaTopFields (md : ByteArray) (schemaObj : Nat) : P (Array ArrowColSpec) := do
  let vt ← match tableVtable md schemaObj with
    | none => throw "Arrow IPC: Schema vtable"
    | some x => pure x
  let fieldsSlot ← match vtableFieldOffset md vt 1 with
    | none => throw "Arrow IPC: Schema.fields missing"
    | some fo => pure (fieldAddr schemaObj fo)
  let vstart ← match followUOffset md fieldsSlot with
    | none => throw "Arrow IPC: fields vector"
    | some vs => pure vs
  if vstart + 4 > md.size then throw "Arrow IPC: fields vector size"
  let n ← match readUInt32LE md vstart with
    | none => throw "Arrow IPC: fields length"
    | some nu => pure nu.toNat
  let mut pos := vstart + 4
  let mut out : Array ArrowColSpec := #[]
  for _ in [:n] do
    if pos + 4 > md.size then throw "Arrow IPC: fields table ref"
    let fo ← match readUInt32LE md pos with
      | none => throw "Arrow IPC: field offset"
      | some u => pure u.toNat
    let fieldObj := pos + fo
    let fvt ← match tableVtable md fieldObj with
      | none => throw "Arrow IPC: field vtable"
      | some x => pure x
    let name ← match vtableFieldOffset md fvt 0 with
      | none => throw "Arrow IPC: Field.name missing"
      | some nfo =>
        match readStringFromSlot md fieldObj nfo with
        | none => throw "Arrow IPC: Field.name"
        | some s => pure s
    let nch ← match vtableFieldOffset md fvt 5 with
      | none => pure 0
      | some co =>
        let cslot := fieldAddr fieldObj co
        match followUOffset md cslot with
        | none => pure 0
        | some cv =>
          match readUInt32LE md cv with
          | none => pure 0
          | some cn => pure cn.toNat
    if nch > 0 then throw "Arrow IPC: nested schema fields not implemented"
    let kind ← parseFieldType md fieldObj
    out := out.push { name := name, kind := kind }
    pos := pos + 4
  pure out

def bufferVecRead (md : ByteArray) (rbObj : Nat) (vtable : Nat) (fieldIdx : Nat) : P (Array (Int64 × Int64)) := do
  let fo ← match vtableFieldOffset md vtable fieldIdx with
    | none => throw "Arrow IPC: RecordBatch field missing"
    | some x => pure x
  let slot := fieldAddr rbObj fo
  let vstart ← match followUOffset md slot with
    | none => throw "Arrow IPC: buffer vector"
    | some vs => pure vs
  if vstart + 4 > md.size then throw "Arrow IPC: buffer vec header"
  let n ← match readUInt32LE md vstart with
    | none => throw "Arrow IPC: buffer vec len"
    | some nu => pure nu.toNat
  let mut pos := vstart + 4
  let mut acc : Array (Int64 × Int64) := #[]
  for _ in [:n] do
    if pos + 16 > md.size then throw "Arrow IPC: Buffer struct"
    let o ← match readInt64LE md pos with
      | none => throw "Arrow IPC: Buffer.offset"
      | some x => pure x
    let len ← match readInt64LE md (pos + 8) with
      | none => throw "Arrow IPC: Buffer.length"
      | some x => pure x
    acc := acc.push (o, len)
    pos := pos + 16
  pure acc

def rbLength (md : ByteArray) (rbObj : Nat) (vtable : Nat) : P Nat := do
  let fo ← match vtableFieldOffset md vtable 0 with
    | none => throw "Arrow IPC: RecordBatch.length missing"
    | some x => pure x
  match readInt64LE md (fieldAddr rbObj fo) with
  | none => throw "Arrow IPC: RecordBatch.length"
  | some n =>
    let i := Int64.toInt n
    if i < 0 then throw "Arrow IPC: negative batch length"
    else pure i.natAbs

def sliceBody (body : ByteArray) (off len : Int64) : P ByteArray := do
  let oi := Int64.toInt off
  let li := Int64.toInt len
  if oi < 0 || li < 0 then throw "Arrow IPC: negative buffer slice"
  else
    let o := oi.natAbs
    let l := li.natAbs
    if o + l > body.size then throw "Arrow IPC: buffer slice OOB"
    else pure (body.extract o (o + l))

def decodePrimitiveColumn (body : ByteArray) (bufs : Array (Int64 × Int64)) (bufIdx : Nat) (rowCount : Nat)
    (kind : ArrowColKind) : P (Array (Option PlainValue) × Nat) := do
  match kind with
  | .int32 =>
    if bufIdx + 1 ≥ bufs.size then throw "Arrow IPC: missing int32 buffers"
    else
      let (_voff, vlen) := bufs[bufIdx]!
      let (_doff, dlen) := bufs[bufIdx + 1]!
      let _ ← sliceBody body _voff vlen
      let data ← sliceBody body _doff dlen
      let need := rowCount * 4
      if data.size < need then throw "Arrow IPC: int32 data short"
      else
        let mut vals : Array (Option PlainValue) := #[]
        let mut p := 0
        for _ in [:rowCount] do
          match readInt32LE data p with
          | none => throw "Arrow IPC: int32 cell"
          | some w => vals := vals.push (some (.int32 w)); p := p + 4
        pure (vals, bufIdx + 2)
  | .int64 =>
    if bufIdx + 1 ≥ bufs.size then throw "Arrow IPC: missing int64 buffers"
    else
      let (_voff, vlen) := bufs[bufIdx]!
      let (_doff, dlen) := bufs[bufIdx + 1]!
      let _ ← sliceBody body _voff vlen
      let data ← sliceBody body _doff dlen
      let need := rowCount * 8
      if data.size < need then throw "Arrow IPC: int64 data short"
      else
        let mut vals : Array (Option PlainValue) := #[]
        let mut p := 0
        for _ in [:rowCount] do
          match readInt64LE data p with
          | none => throw "Arrow IPC: int64 cell"
          | some w => vals := vals.push (some (.int64 w)); p := p + 8
        pure (vals, bufIdx + 2)
  | .bool =>
    if bufIdx + 1 ≥ bufs.size then throw "Arrow IPC: missing bool buffers"
    else
      let (_voff, vlen) := bufs[bufIdx]!
      let (_doff, dlen) := bufs[bufIdx + 1]!
      let _ ← sliceBody body _voff vlen
      let data ← sliceBody body _doff dlen
      match decodePlainBoolsPacked data 0 rowCount with
      | .error e => throw e
      | .ok arr =>
        let vals := arr.map fun pv => some pv
        pure (vals, bufIdx + 2)
  | .float =>
    if bufIdx + 1 ≥ bufs.size then throw "Arrow IPC: missing float buffers"
    else
      let (_voff, vlen) := bufs[bufIdx]!
      let (_doff, dlen) := bufs[bufIdx + 1]!
      let _ ← sliceBody body _voff vlen
      let data ← sliceBody body _doff dlen
      let need := rowCount * 4
      if data.size < need then throw "Arrow IPC: float data short"
      else
        let mut vals : Array (Option PlainValue) := #[]
        let mut p := 0
        for _ in [:rowCount] do
          match readFloat32LE data p with
          | none => throw "Arrow IPC: float cell"
          | some f => vals := vals.push (some (.float f)); p := p + 4
        pure (vals, bufIdx + 2)
  | .double =>
    if bufIdx + 1 ≥ bufs.size then throw "Arrow IPC: missing double buffers"
    else
      let (_voff, vlen) := bufs[bufIdx]!
      let (_doff, dlen) := bufs[bufIdx + 1]!
      let _ ← sliceBody body _voff vlen
      let data ← sliceBody body _doff dlen
      let need := rowCount * 8
      if data.size < need then throw "Arrow IPC: double data short"
      else
        let mut vals : Array (Option PlainValue) := #[]
        let mut p := 0
        for _ in [:rowCount] do
          match readFloat64LE data p with
          | none => throw "Arrow IPC: double cell"
          | some f => vals := vals.push (some (.double f)); p := p + 8
        pure (vals, bufIdx + 2)
  | .binary =>
    if bufIdx + 2 ≥ bufs.size then throw "Arrow IPC: missing binary buffers"
    else
      let (_voff, vlen) := bufs[bufIdx]!
      let (_ooff, olen) := bufs[bufIdx + 1]!
      let (_doff, dlen) := bufs[bufIdx + 2]!
      let _ ← sliceBody body _voff vlen
      let offsets ← sliceBody body _ooff olen
      let needOff := (rowCount + 1) * 4
      if offsets.size < needOff then throw "Arrow IPC: binary offsets"
      else
        let data ← sliceBody body _doff dlen
        let mut vals : Array (Option PlainValue) := #[]
        for ri in [:rowCount] do
          let o0 ← match readInt32LE offsets (ri * 4) with
            | none => throw "Arrow IPC: binary off0"
            | some x => pure (Int32.toInt x).natAbs
          let o1 ← match readInt32LE offsets ((ri + 1) * 4) with
            | none => throw "Arrow IPC: binary off1"
            | some x => pure (Int32.toInt x).natAbs
          if o1 < o0 || o1 > data.size then throw "Arrow IPC: binary slice"
          else vals := vals.push (some (.byteArray (data.extract o0 o1)))
        pure (vals, bufIdx + 3)
  | .utf8 =>
    if bufIdx + 2 ≥ bufs.size then throw "Arrow IPC: missing utf8 buffers"
    else
      let (_voff, vlen) := bufs[bufIdx]!
      let (_ooff, olen) := bufs[bufIdx + 1]!
      let (_doff, dlen) := bufs[bufIdx + 2]!
      let _ ← sliceBody body _voff vlen
      let offsets ← sliceBody body _ooff olen
      let needOff := (rowCount + 1) * 4
      if offsets.size < needOff then throw "Arrow IPC: utf8 offsets"
      else
        let data ← sliceBody body _doff dlen
        let mut vals : Array (Option PlainValue) := #[]
        for ri in [:rowCount] do
          let o0 ← match readInt32LE offsets (ri * 4) with
            | none => throw "Arrow IPC: utf8 off0"
            | some x => pure (Int32.toInt x).natAbs
          let o1 ← match readInt32LE offsets ((ri + 1) * 4) with
            | none => throw "Arrow IPC: utf8 off1"
            | some x => pure (Int32.toInt x).natAbs
          if o1 < o0 || o1 > data.size then throw "Arrow IPC: utf8 slice"
          else vals := vals.push (some (.byteArray (data.extract o0 o1)))
        pure (vals, bufIdx + 3)

def decodeRecordBatch (md : ByteArray) (body : ByteArray) (cols : Array ArrowColSpec) : P Table := do
  let rootU ← match readUInt32LE md 0 with
    | none => throw "Arrow IPC: RB message root"
    | some u => pure u.toNat
  let msgObj := rootU
  let mvt ← match tableVtable md msgObj with
    | none => throw "Arrow IPC: Message vtable"
    | some x => pure x
  let hb ← match vtableFieldOffset md mvt 1 with
    | none => throw "Arrow IPC: Message.header_type missing"
    | some fo => pure (md[fieldAddr msgObj fo]!)
  unless hb == messageHeaderRecordBatch do throw "Arrow IPC: expected RecordBatch message"
  let hslot ← match vtableFieldOffset md mvt 2 with
    | none => throw "Arrow IPC: Message.header missing"
    | some fo => pure (fieldAddr msgObj fo)
  let rbObj ← match followUOffset md hslot with
    | none => throw "Arrow IPC: RecordBatch table"
    | some o => pure o
  let rbvt ← match tableVtable md rbObj with
    | none => throw "Arrow IPC: RecordBatch vtable"
    | some x => pure x
  let rowCount ← rbLength md rbObj rbvt
  let bufs ← bufferVecRead md rbObj rbvt 2
  let mut bufIdx := 0
  let mut tcols : Array Column := #[]
  for spec in cols do
    let (vals, next) ← decodePrimitiveColumn body bufs bufIdx rowCount spec.kind
    bufIdx := next
    tcols := tcols.push { name := spec.name, values := vals }
  unless bufIdx == bufs.size do throw "Arrow IPC: unused buffers after decode"
  pure { columns := tcols }

partial def readArrowIpcStreamFromBytes (b : ByteArray) : P Table :=
  let rec go (pos : Nat) (schema? : Option (Array ArrowColSpec)) : P Table :=
    if pos ≥ b.size then
      match schema? with
      | none => throw "Arrow IPC: stream ended without Schema"
      | some _ => throw "Arrow IPC: stream ended without RecordBatch"
    else if pos + 8 > b.size then throw "Arrow IPC: truncated header"
    else
      match readUInt32LE b pos with
      | none => throw "Arrow IPC: read u32"
      | some cont =>
        let p0 := if cont == 0xffffffff then pos + 4 else pos
        if p0 + 4 > b.size then throw "Arrow IPC: truncated length"
        else
          match readInt32LE b p0 with
          | none => throw "Arrow IPC: read i32"
          | some mlen32 =>
            let mlenI := Int32.toInt mlen32
            if mlenI < 0 then throw "Arrow IPC: negative metadata length"
            else
              let mlen := Int.natAbs mlenI
              if mlen == 0 then
                match schema? with
                | none => throw "Arrow IPC: EOS before Schema"
                | some _ => throw "Arrow IPC: EOS before RecordBatch"
              else do
                let metaStart := p0 + 4
                if metaStart + mlen > b.size then throw "Arrow IPC: truncated metadata"
                else
                  let md := b.extract metaStart (metaStart + mlen)
                  let bodyLen ← messageBodyLength md
                  let afterMeta := metaStart + mlen
                  let bodyOff := align8 afterMeta
                  if bodyOff + bodyLen > b.size then throw "Arrow IPC: truncated body"
                  else
                    let body := b.extract bodyOff (bodyOff + bodyLen)
                    let rootU ← match readUInt32LE md 0 with
                      | none => throw "Arrow IPC: message root"
                      | some u => pure u.toNat
                    let msgObj := rootU
                    let mvt ← match tableVtable md msgObj with
                      | none => throw "Arrow IPC: Message vtable"
                      | some x => pure x
                    let hb ← match vtableFieldOffset md mvt 1 with
                      | none => throw "Arrow IPC: Message.header_type"
                      | some fo => pure (md[fieldAddr msgObj fo]!)
                    if hb == messageHeaderSchema then
                      let hslot ← match vtableFieldOffset md mvt 2 with
                        | none => throw "Arrow IPC: Message.header"
                        | some fo => pure (fieldAddr msgObj fo)
                      let schObj ← match followUOffset md hslot with
                        | none => throw "Arrow IPC: Schema table"
                        | some o => pure o
                      let cols ← parseSchemaTopFields md schObj
                      go (bodyOff + bodyLen) (some cols)
                    else if hb == messageHeaderRecordBatch then
                      match schema? with
                      | none => throw "Arrow IPC: RecordBatch before Schema"
                      | some cols => decodeRecordBatch md body cols
                    else throw s!"Arrow IPC: unsupported MessageHeader {hb.toNat}"
  go 0 none

def readArrowIpcStreamFile (path : System.FilePath) : IO (P Table) := do
  let bytes ← IO.FS.readBinFile path
  pure (readArrowIpcStreamFromBytes bytes)

def fileMagicArrow1 : ByteArray :=
  ByteArray.mk #[65, 82, 82, 79, 87, 49] -- "ARROW1"

def fileHasArrowMagic (b : ByteArray) (off : Nat) : Bool :=
  off + 6 ≤ b.size && b.extract off (off + 6) == fileMagicArrow1

/-- Parse `Footer.recordBatches[0]` → (offset, metadataLength, bodyLength).
`recordBatches` is a vector of inline `Block` structs (not table offsets). -/
def parseFooterFirstRecordBatchBlock (footer : ByteArray) : P (Int64 × Int64 × Int64) := do
  let rootU ← match readUInt32LE footer 0 with
    | none => throw "Arrow IPC file: footer root"
    | some u => pure u.toNat
  let footObj := rootU
  let fvt ← match tableVtable footer footObj with
    | none => throw "Arrow IPC file: Footer vtable"
    | some x => pure x
  let batchesSlot ← match vtableFieldOffset footer fvt 3 with
    | none => throw "Arrow IPC file: Footer.recordBatches missing"
    | some fo => pure (fieldAddr footObj fo)
  let vec ← match followUOffset footer batchesSlot with
    | none => throw "Arrow IPC file: recordBatches vector"
    | some vs => pure vs
  if vec + 4 > footer.size then throw "Arrow IPC file: recordBatches header"
  let n ← match readUInt32LE footer vec with
    | none => throw "Arrow IPC file: recordBatches len"
    | some nu => pure nu.toNat
  if n == 0 then throw "Arrow IPC file: no record batches"
  let blockStart := vec + 4
  if blockStart + 24 > footer.size then throw "Arrow IPC file: Block struct truncated"
  let off ← match readInt64LE footer blockStart with
    | none => throw "Arrow IPC file: Block.offset read"
    | some x => pure x
  let metaLen ← match readInt32LE footer (blockStart + 8) with
    | none => throw "Arrow IPC file: Block.metaDataLength read"
    | some x => pure (Int64.ofInt (Int32.toInt x))
  let bodyLen ← match readInt64LE footer (blockStart + 16) with
    | none => throw "Arrow IPC file: Block.bodyLength read"
    | some x => pure x
  pure (off, metaLen, bodyLen)

def parseFooterSchema (footer : ByteArray) : P (Array ArrowColSpec) := do
  let rootU ← match readUInt32LE footer 0 with
    | none => throw "Arrow IPC file: footer root"
    | some u => pure u.toNat
  let footObj := rootU
  let fvt ← match tableVtable footer footObj with
    | none => throw "Arrow IPC file: Footer vtable"
    | some x => pure x
  let schemaSlot ← match vtableFieldOffset footer fvt 1 with
    | none => throw "Arrow IPC file: Footer.schema missing"
    | some fo => pure (fieldAddr footObj fo)
  let schObj ← match followUOffset footer schemaSlot with
    | none => throw "Arrow IPC file: Schema table"
    | some o => pure o
  parseSchemaTopFields footer schObj

def readArrowIpcFileFromBytes (b : ByteArray) : P Table := do
  if b.size < 14 then throw "Arrow IPC file: too small"
  unless fileHasArrowMagic b 0 do throw "Arrow IPC file: missing leading ARROW1"
  unless fileHasArrowMagic b (b.size - 6) do throw "Arrow IPC file: missing trailing ARROW1"
  let footerLenI ← match readInt32LE b (b.size - 10) with
    | none => throw "Arrow IPC file: footer length"
    | some x => pure (Int32.toInt x)
  if footerLenI < 0 then throw "Arrow IPC file: negative footer length"
  let footerLen := footerLenI.natAbs
  if footerLen + 10 > b.size then throw "Arrow IPC file: footer OOB"
  let footerStart := b.size - 10 - footerLen
  let footer := b.extract footerStart (footerStart + footerLen)
  let cols ← parseFooterSchema footer
  let (offI, metaLenI, bodyLenI) ← parseFooterFirstRecordBatchBlock footer
  let off := Int64.toInt offI
  let metaLen := Int64.toInt metaLenI
  let bodyLen := Int64.toInt bodyLenI
  if off < 0 || metaLen < 0 || bodyLen < 0 then throw "Arrow IPC file: negative block field"
  let pos := off.natAbs
  if pos ≥ b.size then throw "Arrow IPC file: block offset OOB"
  let p0 ← match readUInt32LE b pos with
    | none => throw "Arrow IPC file: block header"
    | some cont =>
      pure (if cont == 0xffffffff then pos + 4 else pos)
  if p0 + 4 > b.size then throw "Arrow IPC file: truncated metadata length"
  let mlenI ← match readInt32LE b p0 with
    | none => throw "Arrow IPC file: metadata length"
    | some x => pure (Int32.toInt x)
  if mlenI < 0 then throw "Arrow IPC file: negative metadata length"
  let mlen := mlenI.natAbs
  let metaStart := p0 + 4
  if metaStart + mlen > b.size then throw "Arrow IPC file: truncated metadata"
  let md := b.extract metaStart (metaStart + mlen)
  let afterMeta := metaStart + mlen
  let bodyOff := align8 afterMeta
  if bodyOff + bodyLen.natAbs > b.size then throw "Arrow IPC file: truncated body"
  let body := b.extract bodyOff (bodyOff + bodyLen.natAbs)
  decodeRecordBatch md body cols

def readArrowIpcFile (path : System.FilePath) : IO (P Table) := do
  let bytes ← IO.FS.readBinFile path
  pure (readArrowIpcFileFromBytes bytes)

end Columnar.Arrow.IPC
