import Init.System.FilePath
import Bench.Registry

namespace Bench

structure ReferenceTiming where
  elapsedMsTotal : Nat
  meanMs : Float
  rowCount : Nat
  deriving Inhabited

def repoRoot : IO System.FilePath := do
  IO.Process.getCurrentDir

def benchReferenceScript : IO System.FilePath := do
  let root ← repoRoot
  pure (root / "scripts" / "bench_reference.py")

def parseNatAfterKey (line key : String) : Except String Nat := do
  let needle := "\"" ++ key ++ "\":"
  let parts := line.splitOn needle
  if parts.length < 2 then
    throw s!"missing {key}"
  let rest := parts[1]!
  let token :=
    match rest.splitOn "," with
    | t :: _ => (t.splitOn "}").head!.trim
    | [] => rest.trim
  match token.toNat? with
  | some n => pure n
  | none => throw s!"bad {key}: {token}"

def parseReferenceJsonLine (line : String) : Except String ReferenceTiming := do
  let line := line.trim
  if line.isEmpty then throw "empty reference output"
  let elapsed ← parseNatAfterKey line "elapsed_ms_total"
  let meanTh ← parseNatAfterKey line "mean_ms_thousandths"
  let rows ← parseNatAfterKey line "row_count"
  pure { elapsedMsTotal := elapsed, meanMs := meanTh.toFloat / 1000.0, rowCount := rows }

def runReferenceTiming (fmt : ReferenceFormat) (path : System.FilePath) (iters : Nat)
    : IO (Except String ReferenceTiming) := do
  if (← IO.getEnv "COLUMNAR_BENCH_SKIP_REFERENCE") == some "1" then
    return .error "reference skipped (COLUMNAR_BENCH_SKIP_REFERENCE=1)"
  let script ← benchReferenceScript
  unless ← script.pathExists do
    return .error s!"missing {script}"
  let args := #["--format", fmt.toCli, "--path", path.toString, "--iters", toString iters]
  let out ←
    IO.Process.output
      { cmd := "python3", args := #["-u", script.toString] ++ args, cwd := (← repoRoot) }
  if out.exitCode != 0 then
    let err := out.stderr.trim
    let msg := if err.isEmpty then s!"exit {out.exitCode}" else err
    return .error msg
  let line :=
    (out.stdout.splitOn "\n").find? (· ≠ "") |>.getD out.stdout.trim
  pure (parseReferenceJsonLine line)

end Bench
