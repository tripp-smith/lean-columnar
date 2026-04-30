import Lake
open System Lake DSL

package columnar where
  version := v!"0.1.0"
  testRunner := "tests"
  -- When using `COLUMNAR_CODEC=1`, add e.g. `-lsnappy -lzstd -lz -lbrotlidec -llz4` here.
  moreLinkArgs := #[]

/-! Native codec static library -/

input_file columnar_codec_c where
  path := "c" / "columnar_codec.c"
  text := true

target columnar_codec_o pkg : System.FilePath := do
  let srcJob ← columnar_codec_c.fetch
  let oFile := pkg.buildDir / "c" / "columnar_codec.o"
  let incl := #[ "-I", (← getLeanIncludeDir).toString ]
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

/-- Registers all `Tests.*` modules so `lean_exe tests` can import them. -/
lean_lib TestsLib where
  roots := #[`Tests.Main]
  globs := #[`Tests.*]

lean_exe tests where
  root := `Tests.Main
  moreLinkObjs := #[libcolumnar_native]

lean_exe bench where
  root := `Bench.Main
  moreLinkObjs := #[libcolumnar_native]
