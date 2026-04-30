**Project Title:** LeanColumnar: High-Performance Zero-Copy Columnar Data Formats for Lean 4

**Repo / Lake Package Name:** `lean-columnar` (GitHub repo) with Lake package name `Columnar`

**Short Description (for README / Reservoir):**  
A pure-Lean 4 Lake package providing high-performance, zero-copy readers and writers for columnar binary formats (Apache Parquet first, with phased support for Avro and ORC). Designed for data engineering and ML workloads, it leverages Lean’s byte arrays and `IO.FS` for memory-mapped I/O and streaming, integrates seamlessly with SciLean for numerical tensors, and offers optional lightweight schema-compatibility proofs. Production-ready, dependency-minimal, and ecosystem-first.

### Comprehensive Project Specification

#### 1. Overview & Motivation
Columnar formats like Parquet dominate modern data lakes (Spark, DuckDB, Polars, Arrow) because they enable predicate pushdown, column pruning, excellent compression, and vectorized analytics—critical for ML pipelines, ETL, and scientific computing.  

Lean 4 excels here: its functional style + high-performance arrays/byte handling + metaprogramming make it ideal for a *native* implementation that is both fast and verifiable. No existing Lean 4 library provides Parquet/Avro/ORC support, making this a genuinely novel, high-impact contribution to the ecosystem (and Reservoir).  

**Core philosophy:**  
- **Programming-first**: Fully functional readers/writers that work out-of-the-box with zero proofs required.  
- **Zero-copy by default**: Data stays in Lean `ByteArray`/`Array` slices until you explicitly materialize.  
- **SciLean-native**: Direct conversion to `SciLean.Data.Tensor` / `FloatMatrix` etc. for seamless ML/scientific workflows.  
- **Lightweight verification**: Optional type-class proofs for schema round-tripping or compatibility (no heavy mathlib dependency).  
- **Lean-native ergonomics**: Derive `ParquetSerializable` via metaprogramming, like Rust’s `serde`.

#### 2. Goals
- **Primary**: Full Parquet 2.x reader + writer (including all encodings, compression codecs, and nested types) with zero-copy decoding and memory-mapped support.  
- **Secondary (phased)**: Avro (row + object container) and ORC support under the same unified API.  
- **Performance**: Match or beat native C++ Arrow/Parquet on columnar scans (benchmarks required).  
- **Usability**: Simple high-level API for data engineers + low-level access for performance hackers.  
- **Ecosystem value**: Become the de-facto standard for columnar I/O in Lean-based data/ML tools.

#### 3. Key Features (Novel Twists Highlighted)
- **Zero-Copy Decoding**  
  - Use Lean’s `ByteArray` slices + `SubArray` views.  
  - Dictionary encoding, RLE, delta, bit-packing, etc., decode directly into borrowed arrays.  
  - No intermediate buffers unless requested.

- **Streaming + Memory-Mapped I/O**  
  - `IO.FS.MemMap` for huge files (zero-copy file → memory).  
  - True streaming readers (process one row-group at a time without full load).  
  - Async-friendly with Lean’s `IO` monad.

- **SciLean Integration** (core novel value)  
  - Automatic conversion: `ParquetTable → SciLean.Tensor` (with shape inference).  
  - Numerical columns (Int64, Float64, etc.) map directly to `SciLean.Data.FloatVec` / `Tensor` for immediate linear algebra / autodiff / optimization.  
  - Example: `let tensor ← parquet.readColumn "features" : SciLean.Tensor (m × n) Float`

- **Optional Lightweight Proofs**  
  - `SchemaCompatible` typeclass with simple round-trip lemmas (e.g., `serialize ∘ deserialize = id`).  
  - No full formal verification required—opt-in for users who want it.

- **Unified API Across Formats**  
  - Common `DataFrame`-like interface (`Table`, `Column`, `RowGroup`).  
  - Metaprogramming-derived serializers (e.g., `#[derive Parquet]`).

- **Compression & Encodings**  
  - Snappy, Zstd, Gzip, Brotli (via Lean FFI to system libs or pure-Lean fallbacks).  
  - All Parquet page encodings supported.

- **Schema Handling**  
  - Full nested structs, lists, maps.  
  - Schema evolution (additive, with compatibility checks).  
  - Arrow schema interop (Parquet → Arrow IPC bridge planned).

#### 4. High-Level API Sketch (Lean 4 syntax)
```lean
-- Core types
structure ParquetFile where
  path : System.FilePath
  metadata : FileMetaData

-- High-level
def readParquet (path : System.FilePath) : IO ParquetTable
def writeParquet (table : ParquetTable) (path : System.FilePath) : IO Unit

-- Zero-copy columnar access
def ParquetTable.getColumn (name : String) : IO (Column α)  -- α inferred or specified

-- SciLean bridge
instance : Coe ParquetColumn SciLean.Tensor where ...

-- Streaming
def streamRowGroups (file : ParquetFile) : IO (Stream RowGroup)

-- Derive example
structure MyRecord where
  id : Nat
  features : Array Float
  label : Bool
deriving ParquetSerializable
```

#### 5. Architecture
- **Layered design** (easy to extend):  
  1. Low-level Thrift metadata parser (Parquet uses Thrift).  
  2. Page/ColumnChunk decoder (zero-copy core).  
  3. RowGroup / Table assembler.  
  4. High-level `Table` + SciLean converters.  
  5. Writer (encoding + compression).

- **Dependencies** (minimal):  
  - `batteries` (standard).  
  - `SciLean` (optional but recommended; soft dependency).  
  - `lean4-parser` or built-in for any text metadata.  
  - FFI only for compression libs (optional pure-Lean Zstd/Snappy later).

- **No external C++ Arrow dependency**—pure Lean for maximum portability and verifiability.

#### 6. Implementation Roadmap (MVP → Full)
**Phase 0 (MVP – 2-4 weeks for solo dev)**  
- Parquet metadata reader + basic flat-table reader (primitive types, Snappy).  
- Zero-copy `ByteArray` decoding for INT32/INT64/FLOAT/DOUBLE.  
- Memory-mapped demo + benchmarks vs. pyarrow.

**Phase 1**  
- Full encodings (RLE, delta, bit-packing).  
- Nested data + lists.  
- SciLean tensor conversion.

**Phase 2**  
- Writer.  
- Streaming + predicate pushdown.  
- Optional schema proofs.

**Phase 3**  
- Avro (Object Container File) support.  
- ORC support (similar columnar layout).  
- Arrow IPC bridge.

#### 7. Testing, Benchmarks & Quality
- **Test suite**: Official Parquet test data + generated round-trips.  
- **Benchmarks**: vs. pyarrow, Polars, DuckDB on real ML datasets (e.g., Hugging Face Parquet files).  
- **CI**: Lake + GitHub Actions (Linux/macOS/Windows).  
- **Docs**: Full manual + examples (CSV ↔ Parquet converter, SciLean ML pipeline).  
- **License**: Apache 2.0 (compatible with Parquet/Arrow).

#### 8. Why This Will Be Popular
- Fills a complete gap—no other Lean columnar I/O exists.  
- SciLean integration makes Lean instantly viable for verified ML/data science.  
- Zero-copy + memory mapping = “Arrow in Lean” performance.  
- Publish to Reservoir → instant adoption by other Lake packages.