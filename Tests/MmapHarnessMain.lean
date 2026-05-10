import Tests.Debug.MmapHarness

/-- Lake `lean_exe mmap_harness` entry (top-level `main` for the linker). -/
def main (args : List String) : IO UInt32 :=
  Tests.Debug.MmapHarness.run args
