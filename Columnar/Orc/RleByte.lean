import Init.Data.ByteArray

namespace Columnar.Orc.RleByte

abbrev P := Except String

/-- ORC byte run-length encoding (boolean and tiny byte columns). -/
partial def decodeByteRle (b : ByteArray) (wantBytes : Nat) : P (Array UInt8) :=
  let rec go (pos : Nat) (acc : Array UInt8) : P (Array UInt8) :=
    if acc.size ≥ wantBytes then pure (acc.extract 0 wantBytes)
    else if pos ≥ b.size then
      if acc.size == wantBytes then pure acc else throw "ORC byte RLE: truncated"
    else
      let c := (b[pos]!).toNat
      if c < 128 then
        let run := c + 3
        if pos + 1 ≥ b.size then throw "ORC byte RLE: truncated run"
        else
          let v := b[pos + 1]!
          let need := wantBytes - acc.size
          let take := min run need
          let rec rep (k : Nat) (a : Array UInt8) : Array UInt8 :=
            if k == 0 then a else rep (k - 1) (a.push v)
          let acc' := rep take acc
          go (pos + 2) acc'
      else
        let lit := 256 - c
        let rec litLoop (k : Nat) (p : Nat) (a : Array UInt8) : P (Array UInt8) :=
          if k == 0 then go p a
          else if p ≥ b.size then throw "ORC byte RLE: truncated literal"
          else litLoop (k - 1) (p + 1) (a.push (b[p]!))
        litLoop lit (pos + 1) acc
  go 0 #[]

/-- Boolean column DATA: byte RLE then MSB-first bits within each byte. -/
def decodeBooleanDataNoNulls (b : ByteArray) (nRows : Nat) : P (Array Bool) := do
  let nbytes := (nRows + 7) / 8
  let bytes ← decodeByteRle b nbytes
  if bytes.isEmpty then throw "ORC boolean: empty RLE"
  else
    let mut out : Array Bool := #[]
    for bv in bytes do
      let v := bv.toNat
      for bit in [0:8] do
        if out.size < nRows then
          let msb := 7 - bit
          out := out.push ((v >>> msb) &&& 1 == 1)
    if out.size < nRows then throw "ORC boolean: short bit run"
    else pure out

end Columnar.Orc.RleByte
