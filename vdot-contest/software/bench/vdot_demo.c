/* vdot.vv demo: the contest's positive / negative / boundary cases.
 *
 * Executes the real instruction (vdot.vv v10, v8, v9 = 0x36942557) on 16-byte
 * register images, prints vs1, vs2 and the complete 128-bit vd, and compares
 * with a scalar reference. vd is pre-filled with 0xff so the printout also
 * shows that vd[127:32] is cleared. Returns non-zero (BAD TRAP) on mismatch.
 */
#include <stdint.h>

#define UART_TX ((volatile uint8_t *)0x40600004UL)
static void putch(char c) { *UART_TX = (uint8_t)c; }
static void puts_(const char *s) { while (*s) putch(*s++); }
static void put_dec(int64_t v) {
  char b[24];
  int n = 0;
  uint64_t u = v < 0 ? (uint64_t)(-v) : (uint64_t)v;
  do { b[n++] = (char)('0' + u % 10); u /= 10; } while (u);
  if (v < 0) putch('-');
  while (n) putch(b[--n]);
}
static void put_hex8(uint8_t x) {
  const char *d = "0123456789abcdef";
  putch(d[x >> 4]);
  putch(d[x & 15]);
}

static void vdot_hw(const int8_t *a, const int8_t *b, uint8_t *vd) {
  __asm__ volatile(
      "vsetivli zero, 16, e8, m1, ta, ma\n\t"
      "vle8.v v8, (%0)\n\t"
      "vle8.v v9, (%1)\n\t"
      "vmv.v.i v10, -1\n\t"
      ".word 0x36942557\n\t" /* vdot.vv v10, v8, v9 */
      "vse8.v v10, (%2)\n\t"
      :
      : "r"(a), "r"(b), "r"(vd)
      : "memory", "v8", "v9", "v10");
}

struct Case {
  const char *name;
  int8_t a[16], b[16];
};

static const struct Case cases[] = {
    {"2.3.1 positive", {1, 2, 3, 4, 5, 6, 7, 8}, {8, 7, 6, 5, 4, 3, 2, 1}},
    {"2.3.2 negative", {-1, -2, -3, -4, -5, -6, -7, -8}, {1, 2, 3, 4, 5, 6, 7, 8}},
    {"2.3.2 mixed sign", {-1, -2, -3, -4, 5, 6, 7, 8}, {8, 7, 6, 5, -4, -3, -2, -1}},
    {"2.3.3 max (-128*-128)", {-128, -128, -128, -128, -128, -128, -128, -128},
     {-128, -128, -128, -128, -128, -128, -128, -128}},
    {"2.3.3 min (-128*127)", {-128, -128, -128, -128, -128, -128, -128, -128},
     {127, 127, 127, 127, 127, 127, 127, 127}},
    {"2.3.3 zero", {0, 0, 0, 0, 0, 0, 0, 0}, {-128, 127, -1, 1, 55, -55, 100, -100}},
    {"2.3.3 high 64b ignored", {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
     {8, 7, 6, 5, 4, 3, 2, 1, -9, -10, -11, -12, -13, -14, -15, -16}},
};

int main(void) {
  int fails = 0;
  static uint8_t vd[16] __attribute__((aligned(16)));
  static int8_t a[16] __attribute__((aligned(16))), b[16] __attribute__((aligned(16)));
  puts_("\n[vdot-demo] vdot.vv v10, v8, v9  (0x36942557)\n");
  for (unsigned c = 0; c < sizeof cases / sizeof cases[0]; c++) {
    for (int i = 0; i < 16; i++) { a[i] = cases[c].a[i]; b[i] = cases[c].b[i]; }
    vdot_hw(a, b, vd);
    int32_t want = 0;
    for (int i = 0; i < 8; i++) want += (int32_t)a[i] * (int32_t)b[i];
    int32_t got = (int32_t)((uint32_t)vd[0] | (uint32_t)vd[1] << 8 | (uint32_t)vd[2] << 16 | (uint32_t)vd[3] << 24);
    int upper_zero = 1;
    for (int i = 4; i < 16; i++) upper_zero &= vd[i] == 0;
    int ok = got == want && upper_zero;
    fails += !ok;
    puts_("case ");
    puts_(cases[c].name);
    puts_("\n  vs1[7:0] = [");
    for (int i = 0; i < 8; i++) { put_dec(a[i]); puts_(i < 7 ? ", " : "]\n"); }
    puts_("  vs2[7:0] = [");
    for (int i = 0; i < 8; i++) { put_dec(b[i]); puts_(i < 7 ? ", " : "]\n"); }
    puts_("  vd       = 0x");
    for (int i = 15; i >= 0; i--) { put_hex8(vd[i]); if (i % 4 == 0 && i) putch('_'); }
    puts_("\n  vd[31:0] = ");
    put_dec(got);
    puts_("  expected ");
    put_dec(want);
    puts_(ok ? "  PASS\n" : "  FAIL\n");
  }
  puts_(fails ? "[vdot-demo] FAIL\n" : "[vdot-demo] all cases PASS\n");
  return fails;
}
