import Init.System.FilePath
import Init.System.IO
import Init.System.Platform

namespace Columnar

/-- POSIX mmap is available (false on WASM / non-Unix stubs). -/
@[extern "columnar_mmap_supported"]
opaque mmapSupportedExtern (_ : Unit) : UInt8

def mmapSupported : Bool :=
  mmapSupportedExtern () != 0

/-- Open path read-only; returns opaque handle (see `columnarMmapHandleLen`). Raises `IO.Error` on failure. -/
@[extern "columnar_mmap_open"]
opaque columnarMmapOpenImpl (path : @& String) : IO USize

@[extern "columnar_mmap_handle_len"]
opaque columnarMmapHandleLen (handle : USize) : IO Nat

@[extern "columnar_mmap_copy_range"]
opaque columnarMmapCopyRangeImpl (handle : USize) (off len : Nat) : IO ByteArray

@[extern "columnar_mmap_close"]
opaque columnarMmapCloseImpl (handle : USize) : IO PUnit

/-- Memory-mapped read-only file region (`mmap` + length). Dispose with `MmapRegion.close`. -/
structure MmapRegion where
  /-- Opaque `columnar_mmap_handle*` as uintptr. -/
  handle : USize
  byteLen : Nat

def MmapRegion.copyRange (m : MmapRegion) (off len : Nat) : IO ByteArray :=
  columnarMmapCopyRangeImpl m.handle off len

def MmapRegion.close (m : MmapRegion) : IO Unit := do
  let _ ← columnarMmapCloseImpl m.handle
  return ()

/-- Open via mmap; on `IO.Error` returns `Except.error` with message string. -/
def mmapOpenTry (path : System.FilePath) : IO (Except String MmapRegion) := do
  match ← IO.getEnv "COLUMNAR_DISABLE_MMAP" with
  | some "1" => return Except.error "COLUMNAR_DISABLE_MMAP=1"
  | _ => pure ()
  /-
    On macOS, mmap + Lean's runtime has been observed to corrupt the heap across `lake exe tests`
    groups (SIGSEGV after the mmap conformance block). Linux CI keeps mmap enabled by default.
    Set `COLUMNAR_FORCE_MMAP=1` on macOS to exercise the native mmap path anyway.
  -/
  if System.Platform.isOSX then
    match ← IO.getEnv "COLUMNAR_FORCE_MMAP" with
    | some "1" => pure ()
    | _ => return Except.error "macOS: mmap open disabled (use COLUMNAR_FORCE_MMAP=1 to enable)"
  unless mmapSupported do
    return Except.error "mmap not supported on this target"
  try
    let h ← columnarMmapOpenImpl path.toString
    let n ← columnarMmapHandleLen h
    return Except.ok ⟨h, n⟩
  catch e =>
    return Except.error (toString e)

/-- Open via mmap; propagates `IO.Error`. Respects the same macOS / disable guards as `mmapOpenTry`. -/
def mmapOpen (path : System.FilePath) : IO MmapRegion := do
  match ← mmapOpenTry path with
  | .ok m => return m
  | .error e => throw (IO.userError e)

def readFileBytes (path : System.FilePath) : IO ByteArray :=
  IO.FS.readBinFile path

end Columnar
