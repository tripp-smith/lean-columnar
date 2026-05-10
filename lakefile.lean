import Lake
open System Lake DSL

/-! Optional SciLean (OpenBLAS): `COLUMNAR_SCILEAN=1 lake update` adds the SciLean `require`; `lake build -Kcolumnar.scilean=1` links BLAS. Wrapper: `scripts/with_scilean.sh`. See README. -/
/-- Whether to `require` SciLean and register `ColumnarSciLean` / `scilean_tests`.
`meta if` conditions are reduced via `evalTerm` and do not reduce `get_config?` reliably; we use
`run_io` to read `COLUMNAR_SCILEAN` (set by `scripts/with_scilean.sh`, which also passes `-Kcolumnar.scilean=1`). -/
abbrev columnarSciLeanPkg : Bool :=
  run_io do
    match (← IO.getEnv "COLUMNAR_SCILEAN") with
    | some v => pure (v == "1" || v == "true")
    | none => pure false

def columnarBlasLinkArgs : Array String :=
  if System.Platform.isWindows then
    #[]
  else if System.Platform.isOSX then
    #["-L/opt/homebrew/opt/openblas/lib", "-L/usr/local/opt/openblas/lib", "-lblas"]
  else
    #["-L/usr/lib/x86_64-linux-gnu/", "-lblas", "-lm"]

meta if columnarSciLeanPkg then do
  require scilean from git "https://github.com/lecopivo/SciLean.git" @ "95f8119a2884e9c41f82136523bd5568ea7075c5"

package columnar where
  version := v!"0.1.0"
  testRunner := "tests"
  -- Link native decompress libs when `lake -Kcolumnar.codec=1` is used (docs/FFI.md).
  -- Link OpenBLAS when SciLean bridge is enabled (`-Kcolumnar.scilean=1`).
  moreLinkArgs :=
    let codec :=
      match get_config? columnar.codec with
      | some _ => #["-lsnappy", "-lzstd", "-lz", "-lbrotlidec", "-llz4"]
      | none => #[]
    let blas := if columnarSciLeanPkg then columnarBlasLinkArgs else #[]
    codec ++ blas

/-! Native codec static library -/

input_file columnar_codec_c where
  path := "c" / "columnar_codec.c"
  text := true

target columnar_codec_o pkg : System.FilePath := do
  let srcJob ← columnar_codec_c.fetch
  let oFile := pkg.buildDir / "c" / "columnar_codec.o"
  let incl := #[ "-I", (← getLeanIncludeDir).toString ]
  -- -DCOLUMNAR_WITH_SYSTEM_CODECS when COLUMNAR_CODEC is set; link libs via lake -Kcolumnar.codec=1
  let codec? ← IO.getEnv "COLUMNAR_CODEC"
  let weak :=
    match codec? with
    | some _ => incl ++ #["-DCOLUMNAR_WITH_SYSTEM_CODECS"]
    | none => incl
  buildO oFile srcJob weak #["-O2", "-fPIC", "-Wall"] "cc"

target libcolumnar_native pkg : System.FilePath := do
  let o ← columnar_codec_o.fetch
  let name := nameToStaticLib "columnar_native"
  buildStaticLib (pkg.staticLibDir / name) #[o]

@[default_target]
lean_lib Columnar where
  roots := #[`Columnar]
  moreLinkObjs := #[libcolumnar_native]

meta if columnarSciLeanPkg then do
  /-- SciLean tensor bridge (`Columnar.SciLean.Convert`). Enable SciLean with `lake update -Kcolumnar.scilean=1`, then `lake build ColumnarSciLean -Kcolumnar.scilean=1`. -/
  lean_lib ColumnarSciLean where
    roots := #[`Columnar.SciLean.Convert]

/-- Registers all `Tests.*` modules so `lean_exe tests` can import them. -/
lean_lib TestsLib where
  roots := #[`Tests.Main]
  globs := #[`Tests.*]

lean_exe tests where
  root := `Tests.Main
  moreLinkObjs := #[libcolumnar_native]

meta if columnarSciLeanPkg then do
  /-- SciLean / OpenBLAS tests (`lake exe scilean_tests -Kcolumnar.scilean=1`). -/
  lean_exe scilean_tests where
    root := `Tests.SciLeanMain
    moreLinkObjs := #[libcolumnar_native]

lean_exe bench where
  root := `Bench.Main
  moreLinkObjs := #[libcolumnar_native]

/-- Canonical writer CLI for Python round-trip smoke (`COLUMNAR_WRITER_PATH`, optional `COLUMNAR_WRITER_SCHEMA`, `COLUMNAR_WRITER_ROWS`). -/
lean_exe writer_roundtrip where
  root := `Bench.WriterRoundtrip
  moreLinkObjs := #[libcolumnar_native]

/-- Isolated mmap FFI + Parquet scenarios for lldb/CI (`scripts/run-mmap-harness.sh`). -/
lean_exe mmap_harness where
  root := `Tests.MmapHarnessMain
  moreLinkObjs := #[libcolumnar_native]
