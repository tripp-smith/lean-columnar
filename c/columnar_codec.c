/*
  LeanColumnar — FFI shims for compression codecs.

  Default build: all codecs are **stubs** (no system headers/libs required).
  Enable real codecs:
    - `export COLUMNAR_CODEC=1` so `columnar_codec.c` is compiled with
      `-DCOLUMNAR_WITH_SYSTEM_CODECS`;
    - `lake build -Kcolumnar.codec=1` so the package links `-lsnappy -lzstd -lz
      -lbrotlidec -llz4` (or use `scripts/with_native_codecs.sh`).
  See docs/FFI.md for OS packages and optional -I/-L flags.
*/
#include <lean/lean.h>
#include <stdio.h>
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
    return mk_user_io_error("columnar: snappy decompress failed: snappy_uncompress");
  }
  lean_sarray_set_size(ba, dst_len);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error(
      "columnar: snappy decompress unavailable: COLUMNAR_CODEC=1 when compiling, "
      "lake -Kcolumnar.codec=1, link -lsnappy (docs/FFI.md)");
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
    char buf[512];
    snprintf(buf, sizeof(buf), "columnar: zstd decompress failed: %s", ZSTD_getErrorName(r));
    return mk_user_io_error(buf);
  }
  lean_sarray_set_size(ba, r);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error(
      "columnar: zstd decompress unavailable: COLUMNAR_CODEC=1 when compiling, "
      "lake -Kcolumnar.codec=1, link -lzstd (docs/FFI.md)");
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
    return mk_user_io_error("columnar: gzip decompress failed (zlib uncompress)");
  }
  lean_sarray_set_size(ba, (size_t)destLen);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error(
      "columnar: gzip decompress unavailable (zlib): COLUMNAR_CODEC=1 when compiling, "
      "lake -Kcolumnar.codec=1, link -lz (docs/FFI.md)");
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
    return mk_user_io_error("columnar: brotli decompress failed: BrotliDecoderDecompress");
  }
  lean_sarray_set_size(ba, avail_out);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error(
      "columnar: brotli decompress unavailable: COLUMNAR_CODEC=1 when compiling, "
      "lake -Kcolumnar.codec=1, link -lbrotlidec (docs/FFI.md)");
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
    return mk_user_io_error("columnar: lz4 decompress failed: LZ4_decompress_safe");
  }
  lean_sarray_set_size(ba, (size_t)r);
  return lean_io_result_mk_ok(ba);
#else
  (void)input;
  (void)dst_cap;
  return mk_user_io_error(
      "columnar: lz4 decompress unavailable: COLUMNAR_CODEC=1 when compiling, "
      "lake -Kcolumnar.codec=1, link -llz4 (docs/FFI.md)");
#endif
}

/* ---- POSIX mmap (same TU as codec shims) ---- */

#if defined(__unix__) && !defined(__EMSCRIPTEN__) && !defined(__wasm__)

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
  void *addr;
  size_t len;
  int fd; /* kept open until munmap */
} columnar_mmap_handle;

/* Lean `USize` carries a small slot id (not a raw C pointer) to avoid ABI / GC edge cases. */
#define COLUMNAR_MMAP_SLOTS 128
static columnar_mmap_handle *columnar_mmap_slots[COLUMNAR_MMAP_SLOTS];

static int columnar_mmap_alloc_slot(columnar_mmap_handle *h) {
  for (int i = 1; i < COLUMNAR_MMAP_SLOTS; i++) {
    if (columnar_mmap_slots[i] == NULL) {
      columnar_mmap_slots[i] = h;
      return i;
    }
  }
  return 0;
}

static columnar_mmap_handle *columnar_mmap_resolve_slot(size_t slot) {
  if (slot == 0 || slot >= COLUMNAR_MMAP_SLOTS) {
    return NULL;
  }
  return columnar_mmap_slots[slot];
}

LEAN_EXPORT uint8_t columnar_mmap_supported(void) { return 1; }

LEAN_EXPORT lean_obj_res columnar_mmap_open(b_lean_obj_arg path_obj, lean_obj_arg w) {
  (void)w;
  char const *path = lean_string_cstr(path_obj);
  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    char buf[512];
    snprintf(buf, sizeof buf, "columnar_mmap_open: open: %s", strerror(errno));
    return mk_user_io_error(buf);
  }
  struct stat st;
  if (fstat(fd, &st) != 0) {
    close(fd);
    char buf[512];
    snprintf(buf, sizeof buf, "columnar_mmap_open: fstat: %s", strerror(errno));
    return mk_user_io_error(buf);
  }
  if (st.st_size == 0) {
    columnar_mmap_handle *h = (columnar_mmap_handle *)malloc(sizeof *h);
    if (!h) {
      close(fd);
      return mk_user_io_error("columnar_mmap_open: malloc");
    }
    h->addr = NULL;
    h->len = 0;
    h->fd = fd;
    int slot = columnar_mmap_alloc_slot(h);
    if (slot == 0) {
      close(fd);
      free(h);
      return mk_user_io_error("columnar_mmap_open: too many concurrent mappings");
    }
    return lean_io_result_mk_ok(lean_box_usize((size_t)slot));
  }
  void *addr = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  if (addr == MAP_FAILED) {
    close(fd);
    char buf[512];
    snprintf(buf, sizeof buf, "columnar_mmap_open: mmap: %s", strerror(errno));
    return mk_user_io_error(buf);
  }
  columnar_mmap_handle *h = (columnar_mmap_handle *)malloc(sizeof *h);
  if (!h) {
    munmap(addr, (size_t)st.st_size);
    close(fd);
    return mk_user_io_error("columnar_mmap_open: malloc");
  }
  h->addr = addr;
  h->len = (size_t)st.st_size;
  h->fd = fd;
  int slot = columnar_mmap_alloc_slot(h);
  if (slot == 0) {
    munmap(addr, (size_t)st.st_size);
    close(fd);
    free(h);
    return mk_user_io_error("columnar_mmap_open: too many concurrent mappings");
  }
  return lean_io_result_mk_ok(lean_box_usize((size_t)slot));
}

LEAN_EXPORT lean_obj_res columnar_mmap_handle_len(b_lean_obj_arg h_box, lean_obj_arg w) {
  (void)w;
  size_t slot = lean_unbox_usize(h_box);
  columnar_mmap_handle *h = columnar_mmap_resolve_slot(slot);
  if (h == NULL) {
    return mk_user_io_error("columnar_mmap_handle_len: invalid handle");
  }
  return lean_io_result_mk_ok(lean_usize_to_nat(h->len));
}

LEAN_EXPORT lean_obj_res columnar_mmap_copy_range(b_lean_obj_arg h_box, b_lean_obj_arg off_nat,
                                                  b_lean_obj_arg len_nat, lean_obj_arg w) {
  (void)w;
  size_t slot = lean_unbox_usize(h_box);
  columnar_mmap_handle *h = columnar_mmap_resolve_slot(slot);
  size_t off = (size_t)lean_uint64_of_nat(off_nat);
  size_t len = (size_t)lean_uint64_of_nat(len_nat);
  if (h == NULL) {
    return mk_user_io_error("columnar_mmap_copy_range: invalid handle");
  }
  if (h->addr == NULL) {
    if (len == 0) {
      lean_obj_res ba = lean_mk_empty_byte_array(lean_box(0));
      return lean_io_result_mk_ok(ba);
    }
    return mk_user_io_error("columnar_mmap_copy_range: empty mapping");
  }
  if (off > h->len || len > h->len - off) {
    return mk_user_io_error("columnar_mmap_copy_range: range out of bounds");
  }
  lean_obj_res ba = lean_mk_empty_byte_array(lean_box(len));
  memcpy(lean_sarray_cptr(ba), (uint8_t const *)h->addr + off, len);
  lean_sarray_set_size(ba, len);
  return lean_io_result_mk_ok(ba);
}

LEAN_EXPORT lean_obj_res columnar_mmap_close(b_lean_obj_arg h_box, lean_obj_arg w) {
  (void)w;
  size_t slot = lean_unbox_usize(h_box);
  if (slot == 0 || slot >= COLUMNAR_MMAP_SLOTS) {
    return lean_io_result_mk_ok(lean_box(0));
  }
  columnar_mmap_handle *h = columnar_mmap_slots[slot];
  if (h != NULL) {
    columnar_mmap_slots[slot] = NULL;
    if (h->addr != NULL && h->len > 0) {
      munmap(h->addr, h->len);
    }
    if (h->fd >= 0) {
      close(h->fd);
    }
    free(h);
  }
  return lean_io_result_mk_ok(lean_box(0));
}

#else

LEAN_EXPORT uint8_t columnar_mmap_supported(void) { return 0; }

LEAN_EXPORT lean_obj_res columnar_mmap_open(b_lean_obj_arg path_obj, lean_obj_arg w) {
  (void)path_obj;
  (void)w;
  return mk_user_io_error("columnar_mmap_open: not supported on this platform (need POSIX mmap)");
}

LEAN_EXPORT lean_obj_res columnar_mmap_handle_len(b_lean_obj_arg h_box, lean_obj_arg w) {
  (void)h_box;
  (void)w;
  return lean_io_result_mk_ok(lean_usize_to_nat(0));
}

LEAN_EXPORT lean_obj_res columnar_mmap_copy_range(b_lean_obj_arg h_box, b_lean_obj_arg off_nat,
                                                  b_lean_obj_arg len_nat, lean_obj_arg w) {
  (void)h_box;
  (void)off_nat;
  (void)len_nat;
  (void)w;
  return mk_user_io_error("columnar_mmap_copy_range: not supported on this platform");
}

LEAN_EXPORT lean_obj_res columnar_mmap_close(b_lean_obj_arg h_box, lean_obj_arg w) {
  (void)h_box;
  (void)w;
  return lean_io_result_mk_ok(lean_box(0));
}

#endif
