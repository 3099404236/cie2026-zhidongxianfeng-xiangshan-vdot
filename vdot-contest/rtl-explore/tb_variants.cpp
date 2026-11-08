// Verilator testbench: streams one new vdot operand pair per cycle through
// every datapath variant (all instantiated in tb_top) and checks each
// variant's vd against a C++ reference 2 cycles later.
//
// Vectors: exhaustive 65536 (a,b) pairs on lane 0 and on lane 7 (other lanes
// random), all-extreme patterns, then N random vectors with random high
// halves (which must be ignored).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>

#include "Vtb_top.h"
#include "verilated.h"
#include "tb_ports.h"   // generated: NUM_VARIANTS, VARIANT_NAMES, read_variant()

struct Vec { uint64_t lo1, hi1, lo2, hi2; };

static int32_t ref_dot(const Vec &v) {
  int32_t s = 0;
  for (int i = 0; i < 8; i++) {
    int8_t a = (int8_t)(v.lo1 >> (8 * i));
    int8_t b = (int8_t)(v.lo2 >> (8 * i));
    s += (int32_t)a * (int32_t)b;
  }
  return s;
}

static void poke(Vtb_top *t, const Vec &v) {
  t->io_vs1[0] = (uint32_t)v.lo1; t->io_vs1[1] = (uint32_t)(v.lo1 >> 32);
  t->io_vs1[2] = (uint32_t)v.hi1; t->io_vs1[3] = (uint32_t)(v.hi1 >> 32);
  t->io_vs2[0] = (uint32_t)v.lo2; t->io_vs2[1] = (uint32_t)(v.lo2 >> 32);
  t->io_vs2[2] = (uint32_t)v.hi2; t->io_vs2[3] = (uint32_t)(v.hi2 >> 32);
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  long n_random = argc > 1 ? atol(argv[1]) : 1000000;
  std::mt19937_64 rng(0x2026);
  std::vector<Vec> vecs;
  auto rnd = [&]() { return rng(); };
  for (int lane : {0, 7})
    for (int a = 0; a < 256; a++)
      for (int b = 0; b < 256; b++) {
        Vec v{rnd(), rnd(), rnd(), rnd()};
        uint64_t m = 0xffull << (8 * lane);
        v.lo1 = (v.lo1 & ~m) | ((uint64_t)a << (8 * lane));
        v.lo2 = (v.lo2 & ~m) | ((uint64_t)b << (8 * lane));
        vecs.push_back(v);
      }
  const uint64_t pats[] = {0, 0x8080808080808080ull, 0x7f7f7f7f7f7f7f7full, 0xffffffffffffffffull,
                           0x807f807f807f807full, 0x0101010101010101ull};
  for (uint64_t p : pats)
    for (uint64_t q : pats) vecs.push_back(Vec{p, ~0ull, q, 0x0123456789abcdefull});
  for (long i = 0; i < n_random; i++) vecs.push_back(Vec{rnd(), rnd(), rnd(), rnd()});

  Vtb_top *t = new Vtb_top;
  t->reset = 1; t->io_en = 0; t->clock = 0; t->eval();
  for (int i = 0; i < 4; i++) { t->clock = 1; t->eval(); t->clock = 0; t->eval(); }
  t->reset = 0;

  // Input j is applied before rising edge j (en=1): the stage-1 register
  // captures it on edge j, the stage-2 register on edge j+1. So right after
  // edge j the output holds the result of input j-1 (back-to-back stream).
  long errors[NUM_VARIANTS] = {0};
  long checked = 0;
  const size_t n = vecs.size();
  for (size_t j = 0; j <= n; j++) {
    if (j < n) { poke(t, vecs[j]); t->io_en = 1; } else t->io_en = 0;
    t->clock = 1; t->eval(); t->clock = 0; t->eval();
    if (j == 0) continue;
    int32_t want = ref_dot(vecs[j - 1]);
    for (int k = 0; k < NUM_VARIANTS; k++) {
      uint32_t lo; bool hi_nonzero;
      read_variant(t, k, lo, hi_nonzero);
      if ((int32_t)lo != want || hi_nonzero) {
        if (errors[k] < 5)
          printf("MISMATCH %s vec#%zu: got %d (hi!=0:%d) want %d\n", VARIANT_NAMES[k], j - 1, (int32_t)lo,
                 hi_nonzero, want);
        errors[k]++;
      }
    }
    checked++;
  }
  int bad = 0;
  for (int k = 0; k < NUM_VARIANTS; k++) {
    printf("%-16s %ld vectors, %ld mismatches\n", VARIANT_NAMES[k], checked, errors[k]);
    bad |= errors[k] != 0;
  }
  delete t;
  return bad;
}
