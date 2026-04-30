import Init.System.IO

/-! Minimal test harness: accumulate failures, exit non-zero if any. -/

namespace Tests.Harness

abbrev ErrLog := IO.Ref (Array String)

def mkLog : IO ErrLog := IO.mkRef #[]

def fail (log : ErrLog) (msg : String) : IO Unit :=
  log.modify (·.push msg)

def check (log : ErrLog) (name : String) (ok : Bool) : IO Unit := do
  unless ok do fail log name

def info (s : String) : IO Unit :=
  IO.println s

def group (title : String) (act : IO Unit) : IO Unit := do
  IO.println s!"── {title} ──"
  act

def finish (log : ErrLog) : IO UInt32 := do
  let es ← log.get
  if es.isEmpty then
    IO.println "Harness: all checks passed."
    return 0
  else
    IO.eprintln "Harness: failures:"
    for e in es do
      IO.eprintln s!"  • {e}"
    return 1

end Tests.Harness
