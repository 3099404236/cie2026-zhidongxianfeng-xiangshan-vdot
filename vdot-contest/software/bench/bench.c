/* vdot.vv vs. RVV 1.0 baseline: latency, throughput and an INT8 GEMV kernel.
 *
 * Runs bare-metal on NEMU (instruction counts) and on the XiangShan emu with
 * difftest (cycle counts). Every kernel's output is checked against a scalar
 * C reference before its numbers are printed; main() returns non-zero (BAD
 * TRAP) on any mismatch.
 */
#include <stdint.h>

typedef int8_t i8;
typedef int32_t i32;
typedef uint64_t u64;

/* kernels in bench_kernels.S */
void k_lat_vdot(u64 iters, const i8 *a, const i8 *b, i8 *out, u64 *ctr);
void k_lat_base_m1(u64 iters, const i8 *a, const i8 *b, i8 *out, u64 *ctr);
void k_lat_base_mf2(u64 iters, const i8 *a, const i8 *b, i8 *out, u64 *ctr);
void k_thr_vdot(u64 iters, const i8 *a, const i8 *b, i8 *out, u64 *ctr);
void k_thr_base(u64 iters, const i8 *a, const i8 *b, i8 *out, u64 *ctr);
void k_gemv_vdot(const i8 *W, const i8 *x, i32 *y, u64 M, u64 K, u64 *ctr);
void k_gemv_base(const i8 *W, const i8 *x, i32 *y, u64 M, u64 K, u64 *ctr);
void k_gemv_rvv(const i8 *W, const i8 *x, i32 *y, u64 M, u64 K, u64 *ctr);
void k_lat_vdota(u64 iters, const i8 *a, const i8 *b, i8 *out, u64 *ctr);
void k_gemv_vdota(const i8 *W, const i8 *x, i32 *y, u64 M, u64 K, u64 *ctr);
void k_gemv_vdota16(const i8 *W, const i8 *x, i32 *y, u64 M, u64 K, u64 *ctr);

/* ---------------------------------------------------------------- output */
#define UART_TX ((volatile uint8_t *)0x40600004UL)

static void putch(char c) { *UART_TX = (uint8_t)c; }
static void puts_(const char *s) { while (*s) putch(*s++); }

static void put_u64(u64 v) {
  char buf[24];
  int n = 0;
  do { buf[n++] = (char)('0' + v % 10); v /= 10; } while (v);
  while (n) putch(buf[--n]);
}

static void put_i64(int64_t v) {
  if (v < 0) { putch('-'); put_u64((u64)(-v)); } else put_u64((u64)v);
}

/* num/den with two decimals, right-aligned to width 8 */
static void put_fix2(u64 num, u64 den) {
  u64 q = num * 100 / den;
  u64 r = q % 100, w = q / 100;
  char buf[24];
  int n = 0;
  buf[n++] = (char)('0' + r % 10);
  buf[n++] = (char)('0' + r / 10);
  buf[n++] = '.';
  do { buf[n++] = (char)('0' + w % 10); w /= 10; } while (w);
  for (int pad = n; pad < 8; pad++) putch(' ');
  while (n) putch(buf[--n]);
}

static void put_pad(const char *s, int width) {
  int n = 0;
  while (s[n]) n++;
  puts_(s);
  for (; n < width; n++) putch(' ');
}

/* ------------------------------------------------------------- reference */
static i32 dot8(const i8 *a, const i8 *b) {
  i32 s = 0;
  for (int i = 0; i < 8; i++) s += (i32)a[i] * (i32)b[i];
  return s;
}

/* Architectural vdot.vv on a 16-byte register image. */
static void vdot_ref(i8 *vd, const i8 *vs1, const i8 *vs2) {
  i32 s = dot8(vs1, vs2);
  for (int i = 0; i < 16; i++) vd[i] = 0;
  for (int i = 0; i < 4; i++) vd[i] = (i8)((uint32_t)s >> (8 * i));
}

#define M 16
#define K 256
static i8 W[M * K] __attribute__((aligned(64)));
static i8 X[K] __attribute__((aligned(64)));
static i32 Y[M], Yref[M];

static uint32_t lcg = 0x2026u;
static i8 rnd8(void) {
  lcg = lcg * 1664525u + 1013904223u;
  return (i8)(lcg >> 24);
}

static int failures;

static void report(const char *name, const u64 *ctr, u64 ops, const char *unit) {
  puts_("  ");
  put_pad(name, 22);
  puts_(" cycles=");
  put_u64(ctr[0]);
  puts_("  instret=");
  put_u64(ctr[1]);
  puts_("  cycles/");
  puts_(unit);
  puts_("=");
  put_fix2(ctr[0], ops);
  puts_("  instr/");
  puts_(unit);
  puts_("=");
  put_fix2(ctr[1], ops);
  putch('\n');
}

static void check(const char *what, int ok) {
  if (!ok) {
    failures++;
    puts_("  MISMATCH: ");
    puts_(what);
    putch('\n');
  }
}

static int same16(const i8 *a, const i8 *b, int n) {
  for (int i = 0; i < n; i++)
    if (a[i] != b[i]) return 0;
  return 1;
}

int main(void) {
  static i8 a[16] __attribute__((aligned(16))) = {3, -7, 11, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8};
  static i8 b[16] __attribute__((aligned(16))) = {-5, 9, -13, 17, 21, -25, 29, -33, 9, 9, 9, 9, 9, 9, 9, 9};
  static i8 out[16] __attribute__((aligned(16)));
  static i8 ref[16];
  u64 ctr[2];
  const u64 lat_iters = 32;   /* x8 dependent ops */
  const u64 thr_iters = 32;   /* x8 independent ops */

  puts_("\n[vdot-bench] XiangShan vdot.vv vs RVV 1.0 baseline\n");

  /* scalar model of the dependent chain (identical for every variant) */
  for (int i = 0; i < 16; i++) ref[i] = a[i];
  for (u64 i = 0; i < lat_iters * 8; i++) {
    i8 t[16];
    vdot_ref(t, ref, b);
    for (int j = 0; j < 16; j++) ref[j] = t[j];
  }

  puts_("latency (dependent chain, 8 per iteration):\n");
  k_lat_vdot(lat_iters, a, b, out, ctr);  /* warm-up: I$ and TLB */
  k_lat_vdot(lat_iters, a, b, out, ctr);
  check("lat_vdot", same16(out, ref, 16));
  report("vdot.vv", ctr, lat_iters * 8, "dot");
  k_lat_base_m1(lat_iters, a, b, out, ctr);
  k_lat_base_m1(lat_iters, a, b, out, ctr);
  check("lat_base_m1", same16(out, ref, 4));
  report("vwmul(m1)+vwredsum", ctr, lat_iters * 8, "dot");
  k_lat_base_mf2(lat_iters, a, b, out, ctr);
  k_lat_base_mf2(lat_iters, a, b, out, ctr);
  check("lat_base_mf2", same16(out, ref, 4));
  report("vwmul(mf2)+vwredsum", ctr, lat_iters * 8, "dot");
  {
    /* vdota chain: acc += dot(a, b), lat_iters * 8 times (int32 wrap) */
    uint32_t acc = 0, d = (uint32_t)dot8(a, b);
    for (u64 i = 0; i < lat_iters * 8; i++) acc += d;
    i8 want[16] = {0};
    for (int i = 0; i < 4; i++) want[i] = (i8)(acc >> (8 * i));
    k_lat_vdota(lat_iters, a, b, out, ctr);
    k_lat_vdota(lat_iters, a, b, out, ctr);
    check("lat_vdota", same16(out, want, 16));
    report("vdota.vv (accumulate)", ctr, lat_iters * 8, "dot");
  }

  puts_("throughput (independent, 8 per iteration):\n");
  vdot_ref(ref, a, b);
  k_thr_vdot(thr_iters, a, b, out, ctr);
  k_thr_vdot(thr_iters, a, b, out, ctr);
  check("thr_vdot", same16(out, ref, 16));
  report("vdot.vv", ctr, thr_iters * 8, "dot");
  k_thr_base(thr_iters, a, b, out, ctr);
  k_thr_base(thr_iters, a, b, out, ctr);
  check("thr_base", same16(out, ref, 4));
  report("vwmul(mf2)+vwredsum", ctr, thr_iters * 8, "dot");

  /* INT8 GEMV, the inner loop of an LLM linear layer (W8A8). */
  for (int i = 0; i < M * K; i++) W[i] = rnd8();
  for (int i = 0; i < K; i++) X[i] = rnd8();
  W[0] = -128; X[0] = -128;   /* exercise the extreme product */
  u64 c0, c1, n0, n1;
  __asm__ volatile("csrr %0, mcycle\n csrr %1, minstret" : "=r"(c0), "=r"(n0));
  for (int r = 0; r < M; r++) {
    i32 s = 0;
    for (int k = 0; k < K; k++) s += (i32)W[r * K + k] * (i32)X[k];
    Yref[r] = s;
  }
  __asm__ volatile("csrr %0, mcycle\n csrr %1, minstret" : "=r"(c1), "=r"(n1));

  puts_("INT8 GEMV M=16 K=256 (4096 MACs):\n");
  ctr[0] = c1 - c0;
  ctr[1] = n1 - n0;
  report("scalar C (-O2)", ctr, M * K / 8, "8MAC");

  for (int v = 0; v < 5; v++) {
    for (int rep = 0; rep < 2; rep++) {  /* second run is reported (warm caches) */
      for (int r = 0; r < M; r++) Y[r] = 0x7eadbeef;
      if (v == 0) k_gemv_vdot(W, X, Y, M, K, ctr);
      if (v == 1) k_gemv_base(W, X, Y, M, K, ctr);
      if (v == 2) k_gemv_rvv(W, X, Y, M, K, ctr);
      if (v == 3) k_gemv_vdota(W, X, Y, M, K, ctr);
      if (v == 4) k_gemv_vdota16(W, X, Y, M, K, ctr);
    }
    int ok = 1;
    for (int r = 0; r < M; r++) ok &= (Y[r] == Yref[r]);
    static const char *names[5] = {"vdot.vv", "vwmul+vwredsum (x8)", "RVV full-width",
                                   "vdota.vv (8B loads)", "vdota.vv (16B+slide)"};
    check(names[v], ok);
    report(names[v], ctr, M * K / 8, "8MAC");
  }

  puts_("y[0..3] = ");
  for (int r = 0; r < 4; r++) { put_i64(Yref[r]); putch(' '); }
  putch('\n');
  puts_(failures ? "[vdot-bench] FAIL\n" : "[vdot-bench] all results match the scalar reference\n");
  return failures;
}
