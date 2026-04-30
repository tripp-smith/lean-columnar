# Native compression (FFI)

`c/columnar_codec.c` exposes decompress entry points used from Lean via `@[extern …]`.

## Default: stubs

Unless `COLUMNAR_CODEC=1` is set in the environment when Lake compiles `columnar_codec.c`, **no**
system codec headers are included and every entry point returns a Lean `IO` user error. This keeps
`lake build` portable (including minimal CI images).

## Enabling system libraries

1. Install development packages, e.g. on Debian/Ubuntu:
   - `libsnappy-dev`, `libzstd-dev`, `zlib1g-dev`, `libbrotli-dev`, `liblz4-dev`
2. Export `COLUMNAR_CODEC=1` and rebuild so Lake passes `-DCOLUMNAR_WITH_SYSTEM_CODECS`.
3. Add link flags on the **package**, for example in `lakefile.lean`:

```lean
package columnar where
  moreLinkArgs := #["-lsnappy", "-lzstd", "-lz", "-lbrotlidec", "-llz4"]
```

4. `lake clean` then `lake build` so the C object file is recompiled.

## macOS / Windows notes

- macOS: headers from Homebrew may need extra `-I/opt/homebrew/include` in the `columnar_codec_o`
  Lake target if the compiler cannot find them.
- Windows: use MSVC + vcpkg and mirror the same libraries; extend `lakefile.lean` with your
  library search paths.
