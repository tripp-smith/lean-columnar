/*
  LeanColumnar — FFI shims for compression codecs.

  Default build: all codecs are **stubs** (no system headers/libs required).
  Enable real codecs: `COLUMNAR_CODEC=1 lake build` (lakefile passes
  `-DCOLUMNAR_WITH_SYSTEM_CODECS`) and set `package` `moreLinkArgs` to your
  platform libraries, e.g. `-lsnappy -lzstd -lz -lbrotlidec -llz4`.
*/
#include <lean/lean.h>
#include <stdlib.h>
#include <string.h>

#ifdef COLUMNAR_WITH_SYSTEM_CODECS

#if __has_include(<snappy-c.h>)
#include <snappy-c.h>
#define COLUMNAR_HAS_SNAPPY 1
#else
#define COLUMNAR_HAS_SNAPPY 0
#endif

#if __has_include(<zstd.h>)
#include <zstd.h>
#define COLUMNAR_HAS_ZSTD 1
#else
#define COLUMNAR_HAS_ZSTD 0
#endif

#if __has_include(<zlib.h>)
#include <zlib.h>
#define COLUMNAR_HAS_ZLIB 1
#else
#define COLUMNAR_HAS_ZLIB 0
#endif

#if __has_include(<brotli/decode.h>)
#include <brotli/decode.h>
#define COLUMNAR_HAS_BROTLI 1
#else
#define COLUMNAR_HAS_BROTLI 0
#endif

#if __has_include(<lz4.h>)
#include <lz4.h>
#define COLUMNAR_HAS_LZ4 1
#else
#define COLUMNAR_HAS_LZ4 0
#endif

#else /* !COLUMNAR_WITH_SYSTEM_CODECS */

#define COLUMNAR_HAS_SNAPPY 0
#define COLUMNAR_HAS_ZSTD 0
#define COLUMNAR_HAS_ZLIB 0
#define COLUMNAR_HAS_BROTLI 0
#define COLUMNAR_HAS_LZ4 0

#endif

static lean_obj_res mk_user_io_error(char const * msg) {
  lean_obj_res s = lean_mk_string(msg);
  if (!lean_is_exclusive(s)) { lean_inc(s); }
  lean_obj_res e = lean_mk_io_user_error(s);
  lean_dec(s);
  return lean_io_result_mk_error(e);
}

#if (COLUMNAR_HAS_SNAPPY || COLUMNAR_HAS_ZSTD || COLUMNAR_HAS_ZLIB || COLUMNAR_HAS_BROTLI || COLUMNAR_HAS_LZ4)
static uint8_t const * ba_ptr(b_lean_obj_arg a) { return lean_sarray_cptr(a); }
static size_t ba_size(b_lean_obj_arg a) { return lean_sarray_size(a); }
#endif

LEAN_EXPORT lean_obj_res columnar_snappy_decompress(b_lean_obj_arg input, size_t dst_cap, lean_obj_arg w) {
  (void)w;
#if COLUMNAR_HAS_SNAPPY
  size_t n = ba_size(input);
  uint8_t const * src = ba_ptr(input);
  lean_obj_res ba = lean_mk_empty_byte_array(lean_box(dst_cap));
  size_t dst_len = dst_cap;
  snappy_status st = snappy_uncompress((char const *)src, n, (char *)lean_sarray_cptr(ba), &dst_len);
  if (st != SNAPPY_OK) {
    lean_dec(ba);
    return mk_user_io_error("snappy_uncompress failed");
  }
  lean_sarray_set_size(ba, dst_len);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error("columnar: snappy FFI disabled (set COLUMNAR_CODEC=1 + link libsnappy)");
#endif
}

LEAN_EXPORT lean_obj_res columnar_zstd_decompress(b_lean_obj_arg input, size_t dst_cap, lean_obj_arg w) {
  (void)w;
#if COLUMNAR_HAS_ZSTD
  size_t n = ba_size(input);
  uint8_t const * src = ba_ptr(input);
  lean_obj_res ba = lean_mk_empty_byte_array(lean_box(dst_cap));
  size_t r = ZSTD_decompress(lean_sarray_cptr(ba), dst_cap, src, n);
  if (ZSTD_isError(r)) {
    lean_dec(ba);
    return mk_user_io_error(ZSTD_getErrorName(r));
  }
  lean_sarray_set_size(ba, r);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error("columnar: zstd FFI disabled (set COLUMNAR_CODEC=1 + link libzstd)");
#endif
}

LEAN_EXPORT lean_obj_res columnar_zlib_decompress(b_lean_obj_arg input, size_t dst_cap, lean_obj_arg w) {
  (void)w;
#if COLUMNAR_HAS_ZLIB
  size_t n = ba_size(input);
  uint8_t const * src = ba_ptr(input);
  lean_obj_res ba = lean_mk_empty_byte_array(lean_box(dst_cap));
  uLongf destLen = (uLongf)dst_cap;
  int zst = uncompress(lean_sarray_cptr(ba), &destLen, src, (uLong)n);
  if (zst != Z_OK) {
    lean_dec(ba);
    return mk_user_io_error("zlib uncompress failed");
  }
  lean_sarray_set_size(ba, (size_t)destLen);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error("columnar: zlib FFI disabled (set COLUMNAR_CODEC=1 + link -lz)");
#endif
}

LEAN_EXPORT lean_obj_res columnar_brotli_decompress(b_lean_obj_arg input, size_t dst_cap, lean_obj_arg w) {
  (void)w;
#if COLUMNAR_HAS_BROTLI
  size_t n = ba_size(input);
  uint8_t const * src = ba_ptr(input);
  lean_obj_res ba = lean_mk_empty_byte_array(lean_box(dst_cap));
  size_t avail_out = dst_cap;
  BROTLI_DECODER_RESULT res = BrotliDecoderDecompress(src, n, lean_sarray_cptr(ba), &avail_out);
  if (res != BROTLI_DECODER_RESULT_SUCCESS) {
    lean_dec(ba);
    return mk_user_io_error("BrotliDecoderDecompress failed");
  }
  lean_sarray_set_size(ba, avail_out);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error("columnar: brotli FFI disabled (set COLUMNAR_CODEC=1 + link libbrotli)");
#endif
}

LEAN_EXPORT lean_obj_res columnar_lz4_decompress(b_lean_obj_arg input, size_t dst_cap, lean_obj_arg w) {
  (void)w;
#if COLUMNAR_HAS_LZ4
  size_t n = ba_size(input);
  uint8_t const * src = ba_ptr(input);
  lean_obj_res ba = lean_mk_empty_byte_array(lean_box(dst_cap));
  int r = LZ4_decompress_safe((char const *)src, (char *)lean_sarray_cptr(ba), (int)n, (int)dst_cap);
  if (r < 0) {
    lean_dec(ba);
    return mk_user_io_error("LZ4_decompress_safe failed");
  }
  lean_sarray_set_size(ba, (size_t)r);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error("columnar: lz4 FFI disabled (set COLUMNAR_CODEC=1 + link liblz4)");
#endif
}
