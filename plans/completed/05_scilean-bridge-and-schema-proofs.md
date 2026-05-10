# Plan: SciLean tensor bridge and optional schema proofs

**Status:** Completed (see completion summary at bottom).

## Objective

Fulfill **spec.md** SciLean integration and lightweight verification: real tensor coercions from columnar data, optional `SchemaCompatible` / round-trip lemmas where total.

## Implementation requirements

### SciLean dependency (optional Lake target)

- Add **`SciLean`** as an optional Lake dependency (separate `lean_lib` or feature flag) so default builds stay minimal.
- Implement **`Coe` / `TensorBridge`** (or dedicated `toTensor`) for numeric columns: shape `rows × 1` or `rows × k` for k primitive columns with compatible types; document unsupported combinations.

### Tests

- Property or golden tests: shape matches row count, `FloatArray` / tensor equality within tolerance for float columns.
- Optional law: `toTable ∘ fromTensor ≈ id` on generators where defined.

### Proofs (`Columnar/Parquet/Proofs.lean`)

- Replace stub with **documented** lemmas only where encoders/decoders are total: e.g. PLAIN int32 round-trip under fixed schema, or schema compatibility as a typeclass with Decidable instances for a small schema DSL.

## Acceptance criteria

- `lake build` default package unchanged for users without SciLean.
- Optional target builds and `lake exe tests` (or a dedicated `lake exe scilean-tests`) passes SciLean-guarded tests when enabled.
- At least one non-trivial proof or `sorry`-free lemma checked in CI for the chosen minimal scope.

## Key code

- `Columnar/SciLean/Tensor.lean`, `lakefile.lean`, `Tests/Unit/SciLeanBridge.lean` (extend), `Columnar/Parquet/Proofs.lean`

## Dependencies

- **04** (typed column / slice view) strongly simplifies tensor extraction.

---

## Completion summary (2026)

| Deliverable | Notes |
|-------------|--------|
| Optional SciLean packaging | `lake-manifest.json` commits with **`packages: []`**. SciLean is **`require`’d** only when **`COLUMNAR_SCILEAN=1`** is set during elaboration (`abbrev columnarSciLeanPkg := run_io …`); **`meta if` + `get_config?` alone is unreliable under Lake `evalTerm`**. **`scripts/with_scilean.sh`** sets `COLUMNAR_SCILEAN` and passes **`-Kcolumnar.scilean=1`** for `moreLinkArgs` / OpenBLAS. **`ColumnarSciLean`** + **`scilean_tests`** registered under the same guard. |
| Tensor bridge | **`Columnar/SciLean/Convert.lean`**: homogeneous **`float` / `double` / `int32`** → row-major **`DataArray Float`**; **`plainInt32PackedBytes?`** fast path; **`floatDataArrayToTable`** inverse (doubles). **`TensorBridge`** rows/cols in **`Columnar/SciLean/Tensor.lean`**. |
| Proofs | **`Columnar/Parquet/Proofs.lean`**: Decidable **`FlatPhys` / `FlatSchema`**, **`plain_int32_roundtrip_demo`** (`rfl` constant-fold). Full **`∀ i : Int32`** PLAIN lemma deferred (UInt32 byte-recombine finisher is awkward without Mathlib-grade BitVec tactics). |
| Tests | **`Tests/SciLeanMain`**, **`Tests/SciLean/Unit`**: shape, tolerance, **`tableToFloatDataArray` ∘ `floatDataArrayToTable`** round-trip on doubles. **`Tests/Unit/SciLeanBridge`**: default shim. |
| CI | **`.github/workflows/ci.yml`** job **`scilean-bridge`** (Ubuntu: **`libopenblas-dev`**, **`COLUMNAR_SCILEAN=1 lake update`**, build **`ColumnarSciLean`**, **`scilean_tests`**). |
| Docs | **`README.md`** (quick start + status link), **`docs/Conformance.md`** (SciLean section + matrix row). |

**Deferred:** unconditional **`∀ Int32`** PLAIN round-trip proof in **`Proofs.lean`**; local SciLean build requires system OpenBLAS/cblas headers (CI installs **`libopenblas-dev`**).
