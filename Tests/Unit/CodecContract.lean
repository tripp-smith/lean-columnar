import Init.Data.ByteArray
import Init.System.IO
import Init.System.FilePath
import Columnar.Compression.Codec
import Tests.Fixtures
import Tests.Harness

namespace Tests.Unit.CodecContract

open Columnar.Compression

def expectedPlainSize : Nat := 37

def readCodecFixture (name : String) : IO ByteArray := do
  let p := Fixtures.codecContractDir / name
  IO.FS.readBinFile p

/-- If any fixture round-trips, native codec FFI is active. -/
def detectNative (plain : ByteArray) : IO Bool := do
  for (file, cid) in
      [("snappy.bin", CodecId.snappy), ("zlib.bin", CodecId.gzip), ("zstd.bin", CodecId.zstd)] do
    try
      let input ← readCodecFixture file
      let out ← decompress cid input plain.size
      if out == plain then return true
    catch _ => pure ()
  pure false

def assertStubMsg (ctx : Harness.Ctx) (codecLabel : String) (msg : String) : IO Unit := do
  Harness.check ctx s!"stub {codecLabel} names codec" (msg.contains codecLabel)
  Harness.check ctx s!"stub {codecLabel} mentions COLUMNAR_CODEC or unavailable"
    (msg.contains "COLUMNAR_CODEC" || msg.contains "unavailable")

def runStub (ctx : Harness.Ctx) (plain : ByteArray) : IO Unit := do
  let pairs : List (String × CodecId × String) :=
    [
      ("snappy.bin", CodecId.snappy, "snappy"),
      ("zlib.bin", CodecId.gzip, "gzip"),
      ("zstd.bin", CodecId.zstd, "zstd"),
      ("brotli.bin", CodecId.brotli, "brotli"),
      ("lz4_raw.bin", CodecId.lz4Raw, "lz4")
    ]
  for (file, cid, key) in pairs do
    let input ← readCodecFixture file
    try
      let _ ← decompress cid input plain.size
      Harness.fail ctx s!"codec contract: expected stub failure for {key}"
    catch e =>
      assertStubMsg ctx key e.toString

def runNative (ctx : Harness.Ctx) (plain : ByteArray) : IO Unit := do
  let checks : List (String × CodecId) :=
    [
      ("snappy.bin", CodecId.snappy),
      ("zlib.bin", CodecId.gzip),
      ("zstd.bin", CodecId.zstd),
      ("brotli.bin", CodecId.brotli),
      ("lz4_raw.bin", CodecId.lz4Raw)
    ]
  for (file, cid) in checks do
    let input ← readCodecFixture file
    try
      let out ← decompress cid input plain.size
      Harness.check ctx s!"codec {repr cid} round-trip" (out == plain)
    catch e =>
      let msg := e.toString
      if msg.contains "unavailable" || msg.contains "COLUMNAR_CODEC" then
        Harness.info s!"codec contract native {repr cid}: SKIP ({msg})"
      else
        Harness.fail ctx s!"codec contract native {repr cid}: {msg}"

def run (ctx : Harness.Ctx) : IO Unit := do
  unless ← Fixtures.codecContractDir.pathExists do
    Harness.info "Codec contract: SKIP (Tests/fixtures/codecs missing; run scripts/gen_codec_contract_fixtures.py)"
    return
  let plain ← readCodecFixture "plaintext.bin"
  unless plain.size == expectedPlainSize do
    Harness.fail ctx s!"codec contract: plaintext.bin size {plain.size} expected {expectedPlainSize}"
    return
  let native? ← detectNative plain
  if native? then runNative ctx plain else runStub ctx plain

end Tests.Unit.CodecContract
